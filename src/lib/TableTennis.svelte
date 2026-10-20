<script lang="ts">
  import { onMount } from 'svelte'

  // ── Constants ──────────────────────────────────────
  const CANVAS_W = 900
  const CANVAS_H = 600
  const TABLE_MARGIN = 40
  const PADDLE_W = 18
  const PADDLE_H = 100
  const BALL_RADIUS = 11
  const MAX_BALL_SPEED = 17
  const INITIAL_BALL_SPEED = 6.5
  const WINNING_SCORE = 11
  const TRAIL_LENGTH = 16
  const SERVE_DELAY_FRAMES = 90

  const TX = TABLE_MARGIN
  const TY = TABLE_MARGIN
  const TW = CANVAS_W - 2 * TABLE_MARGIN
  const TH = CANVAS_H - 2 * TABLE_MARGIN
  const NET_X = CANVAS_W / 2

  const LEFT_COLOR = '#3bb4f7'
  const RIGHT_COLOR = '#ff7849'

  // ── Types ──────────────────────────────────────────
  interface Ball {
    x: number
    y: number
    vx: number
    vy: number
    radius: number
    trail: { x: number; y: number }[]
  }

  interface Paddle {
    x: number
    y: number
    vx: number
    vy: number
    w: number
    h: number
    team: number
    minX: number
    maxX: number
    minY: number
    maxY: number
    up: string
    down: string
    left: string
    right: string
    squash: number
  }

  interface Particle {
    x: number
    y: number
    vx: number
    vy: number
    life: number
    maxLife: number
    color: string
    size: number
  }

  // ── Reactive state (template-facing) ───────────────
  let gameState = $state<'menu' | 'playing' | 'gameover'>('menu')
  let scores = $state<[number, number]>([0, 0])
  let rallyCount = $state(0)
  let winner = $state(-1)
  let leftMouseMode = $state(false)
  let rightMouseMode = $state(false)
  let savedProgress = $state<SavedState | null>(null)

  // ── Local storage persistence ──────────────────────
  const STORAGE_KEY = 'table-tennis-1v1'

  interface SavedState {
    gameState: 'menu' | 'playing' | 'gameover'
    scores: [number, number]
    rallyCount: number
    winner: number
    leftMouseMode: boolean
    rightMouseMode: boolean
    servingDirection: number
  }

  function saveState() {
    const data: SavedState = {
      gameState,
      scores: [...scores] as [number, number],
      rallyCount,
      winner,
      leftMouseMode,
      rightMouseMode,
      servingDirection,
    }
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
    } catch {
      // localStorage may be unavailable (private mode, quota)
    }
  }

  function loadState(): SavedState | null {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      if (!raw) return null
      const data = JSON.parse(raw) as SavedState
      if (!data || !Array.isArray(data.scores) || data.scores.length !== 2) return null
      return data
    } catch {
      return null
    }
  }

  function clearSavedState() {
    try {
      localStorage.removeItem(STORAGE_KEY)
    } catch {
      // ignore
    }
  }

  // Auto-save whenever reactive state changes (after initial settings restore)
  let initialized = false
  $effect(() => {
    gameState
    scores
    rallyCount
    winner
    leftMouseMode
    rightMouseMode
    servingDirection
    if (initialized) saveState()
  })

  // ── Non-reactive game objects ──────────────────────
  let canvas: HTMLCanvasElement
  let ctx: CanvasRenderingContext2D
  let ball: Ball
  let paddles: Paddle[]
  let particles: Particle[] = []
  let keys = new Set<string>()
  let animationId = 0
  let serveDelay = 0
  let servingDirection = 1
  let audioCtx: AudioContext | null = null
  let shakeX = 0
  let shakeY = 0
  let shakeIntensity = 0
  let mouseY = 0
  let mouseInside = false

  // ── Audio ──────────────────────────────────────────
  function initAudio() {
    if (!audioCtx) {
      audioCtx = new (window.AudioContext || (window as any).webkitAudioContext)()
    }
  }

  function playSound(freq: number, duration: number, type: OscillatorType = 'square', volume = 0.1) {
    if (!audioCtx) return
    const osc = audioCtx.createOscillator()
    const gain = audioCtx.createGain()
    osc.type = type
    osc.frequency.value = freq
    gain.gain.setValueAtTime(volume, audioCtx.currentTime)
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + duration)
    osc.connect(gain)
    gain.connect(audioCtx.destination)
    osc.start()
    osc.stop(audioCtx.currentTime + duration)
  }

  // ── Initialization ─────────────────────────────────
  function createPaddles(): Paddle[] {
    const leftMaxX = NET_X - PADDLE_W - 4
    const rightMinX = NET_X + 4
    const py = TY + TH / 2 - PADDLE_H / 2

    return [
      {
        x: TX + 60, y: py, vx: 0, vy: 0, w: PADDLE_W, h: PADDLE_H,
        team: 0,
        minX: TX + 5, maxX: leftMaxX, minY: TY + 5, maxY: TY + TH - PADDLE_H - 5,
        up: 'w', down: 's', left: 'a', right: 'd',
        squash: 1,
      },
      {
        x: TX + TW - 60 - PADDLE_W, y: py, vx: 0, vy: 0, w: PADDLE_W, h: PADDLE_H,
        team: 1,
        minX: rightMinX, maxX: TX + TW - PADDLE_W - 5, minY: TY + 5, maxY: TY + TH - PADDLE_H - 5,
        up: 'arrowup', down: 'arrowdown', left: 'arrowleft', right: 'arrowright',
        squash: 1,
      },
    ]
  }

  function createBall(): Ball {
    return { x: CANVAS_W / 2, y: CANVAS_H / 2, vx: 0, vy: 0, radius: BALL_RADIUS, trail: [] }
  }

  function serveBall(direction: number) {
    ball.x = CANVAS_W / 2
    ball.y = CANVAS_H / 2 + (Math.random() - 0.5) * 100
    const angle = (Math.random() - 0.5) * 0.5
    ball.vx = direction * INITIAL_BALL_SPEED * Math.cos(angle)
    ball.vy = INITIAL_BALL_SPEED * Math.sin(angle)
    ball.trail = []
  }

  // ── Game logic ─────────────────────────────────────
  function update() {
    if (serveDelay > 0) {
      serveDelay--
      if (serveDelay === 0) serveBall(servingDirection)
      // Still allow paddle movement during serve delay
      updatePaddles()
      return
    }

    updatePaddles()

    // Move ball
    ball.x += ball.vx
    ball.y += ball.vy

    // Trail
    ball.trail.push({ x: ball.x, y: ball.y })
    if (ball.trail.length > TRAIL_LENGTH) ball.trail.shift()

    // Top/bottom wall bounce
    if (ball.y - ball.radius < TY) {
      ball.y = TY + ball.radius
      ball.vy = Math.abs(ball.vy)
      playSound(200, 0.04, 'sine', 0.06)
    }
    if (ball.y + ball.radius > TY + TH) {
      ball.y = TY + TH - ball.radius
      ball.vy = -Math.abs(ball.vy)
      playSound(200, 0.04, 'sine', 0.06)
    }

    // Paddle collision
    for (const p of paddles) {
      if (p.team === 0 && ball.vx >= 0) continue
      if (p.team === 1 && ball.vx <= 0) continue

      if (
        ball.x + ball.radius >= p.x &&
        ball.x - ball.radius <= p.x + p.w &&
        ball.y + ball.radius >= p.y &&
        ball.y - ball.radius <= p.y + p.h
      ) {
        const centerY = p.y + p.h / 2
        const offset = Math.max(-1, Math.min(1, (ball.y - centerY) / (p.h / 2)))
        const speed = Math.min(Math.hypot(ball.vx, ball.vy) * 1.07, MAX_BALL_SPEED)
        const angle = offset * 0.6

        ball.vx = (p.team === 0 ? 1 : -1) * speed * Math.cos(angle)
        ball.vy = speed * Math.sin(angle)

        // Add paddle velocity influence for "english"
        ball.vy += p.vy * 0.25

        if (Math.abs(offset) < 0.08) ball.vy += (Math.random() - 0.5) * 1.5

        // Push ball out of paddle
        ball.x = p.team === 0 ? p.x + p.w + ball.radius + 1 : p.x - ball.radius - 1

        // Squash effect
        p.squash = 0.6

        rallyCount++
        spawnHitParticles(ball.x, ball.y, p.team === 0 ? LEFT_COLOR : RIGHT_COLOR)
        shakeIntensity = Math.min(6, rallyCount * 0.15)
        playSound(360 + rallyCount * 10, 0.07, 'square', 0.09)
      }
    }

    // Scoring
    if (ball.x + ball.radius < TX) {
      scorePoint(1)
    } else if (ball.x - ball.radius > TX + TW) {
      scorePoint(0)
    }

    // Update particles
    for (let i = particles.length - 1; i >= 0; i--) {
      const p = particles[i]
      p.x += p.vx
      p.y += p.vy
      p.vy += 0.12
      p.life--
      if (p.life <= 0) particles.splice(i, 1)
    }

    // Update squash recovery
    for (const p of paddles) {
      p.squash += (1 - p.squash) * 0.15
    }

    // Screen shake decay
    shakeIntensity *= 0.85
    shakeX = (Math.random() - 0.5) * shakeIntensity
    shakeY = (Math.random() - 0.5) * shakeIntensity
  }

  function updatePaddles() {
    const accel = 1.2
    const friction = 0.82
    const maxSpeed = 9

    for (const p of paddles) {
      const idx = paddles.indexOf(p)
      const useMouse = (idx === 0 && leftMouseMode) || (idx === 1 && rightMouseMode)

      if (useMouse && mouseInside) {
        // Mouse control: smooth follow
        const targetY = mouseY - p.h / 2
        const diff = targetY - p.y
        p.vy = Math.max(-maxSpeed, Math.min(maxSpeed, diff * 0.25))
        p.vx *= friction
      } else {
        // Keyboard: acceleration-based
        let ax = 0, ay = 0
        if (keys.has(p.up)) ay -= accel
        if (keys.has(p.down)) ay += accel
        if (keys.has(p.left)) ax -= accel
        if (keys.has(p.right)) ax += accel

        p.vx += ax
        p.vy += ay
        p.vx *= friction
        p.vy *= friction

        p.vx = Math.max(-maxSpeed, Math.min(maxSpeed, p.vx))
        p.vy = Math.max(-maxSpeed, Math.min(maxSpeed, p.vy))
      }

      p.x += p.vx
      p.y += p.vy

      // Clamp position
      if (p.x < p.minX) { p.x = p.minX; p.vx = 0 }
      if (p.x > p.maxX) { p.x = p.maxX; p.vx = 0 }
      if (p.y < p.minY) { p.y = p.minY; p.vy = 0 }
      if (p.y > p.maxY) { p.y = p.maxY; p.vy = 0 }
    }
  }

  function scorePoint(team: number) {
    scores[team]++
    playSound(team === 0 ? 320 : 260, 0.35, 'sawtooth', 0.08)
    spawnScoreParticles(ball.x, ball.y, team === 0 ? LEFT_COLOR : RIGHT_COLOR)
    shakeIntensity = 8

    if (scores[team] >= WINNING_SCORE) {
      gameState = 'gameover'
      winner = team
      playSound(500, 0.5, 'sine', 0.12)
      return
    }

    rallyCount = 0
    servingDirection = team === 0 ? 1 : -1
    ball.x = CANVAS_W / 2
    ball.y = CANVAS_H / 2
    ball.vx = 0
    ball.vy = 0
    ball.trail = []
    serveDelay = SERVE_DELAY_FRAMES
  }

  function spawnHitParticles(x: number, y: number, color: string) {
    for (let i = 0; i < 12; i++) {
      const angle = Math.random() * Math.PI * 2
      const speed = 1 + Math.random() * 4
      particles.push({ x, y, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - 1, life: 30, maxLife: 30, color, size: 2 + Math.random() * 2 })
    }
  }

  function spawnScoreParticles(x: number, y: number, color: string) {
    for (let i = 0; i < 30; i++) {
      const angle = Math.random() * Math.PI * 2
      const speed = 2 + Math.random() * 6
      particles.push({ x, y, vx: Math.cos(angle) * speed, vy: Math.sin(angle) * speed - 2, life: 45, maxLife: 45, color, size: 2 + Math.random() * 3 })
    }
  }

  // ── Drawing ────────────────────────────────────────
  function roundRect(x: number, y: number, w: number, h: number, r: number) {
    ctx.beginPath()
    ctx.moveTo(x + r, y)
    ctx.arcTo(x + w, y, x + w, y + h, r)
    ctx.arcTo(x + w, y + h, x, y + h, r)
    ctx.arcTo(x, y + h, x, y, r)
    ctx.arcTo(x, y, x + w, y, r)
    ctx.closePath()
  }

  function draw() {
    ctx.save()
    ctx.translate(shakeX, shakeY)

    // Background
    const bgGrad = ctx.createRadialGradient(CANVAS_W / 2, CANVAS_H / 2, 80, CANVAS_W / 2, CANVAS_H / 2, 650)
    bgGrad.addColorStop(0, '#15172a')
    bgGrad.addColorStop(1, '#0a0b14')
    ctx.fillStyle = bgGrad
    ctx.fillRect(-10, -10, CANVAS_W + 20, CANVAS_H + 20)

    // Table shadow
    ctx.shadowColor = 'rgba(0,0,0,0.6)'
    ctx.shadowBlur = 25
    ctx.shadowOffsetY = 6

    // Table surface
    const tableGrad = ctx.createLinearGradient(0, TY, 0, TY + TH)
    tableGrad.addColorStop(0, '#1e5631')
    tableGrad.addColorStop(0.5, '#194a29')
    tableGrad.addColorStop(1, '#1e5631')
    ctx.fillStyle = tableGrad
    roundRect(TX, TY, TW, TH, 8)
    ctx.fill()

    ctx.shadowColor = 'transparent'
    ctx.shadowBlur = 0
    ctx.shadowOffsetY = 0

    // Table border
    ctx.strokeStyle = 'rgba(255,255,255,0.12)'
    ctx.lineWidth = 2
    roundRect(TX, TY, TW, TH, 8)
    ctx.stroke()

    // Faint score numbers on table
    ctx.font = 'bold 130px system-ui, sans-serif'
    ctx.textAlign = 'center'
    ctx.textBaseline = 'middle'
    ctx.fillStyle = 'rgba(59, 180, 247, 0.07)'
    ctx.fillText(String(scores[0]), CANVAS_W * 0.25, CANVAS_H / 2)
    ctx.fillStyle = 'rgba(255, 120, 73, 0.07)'
    ctx.fillText(String(scores[1]), CANVAS_W * 0.75, CANVAS_H / 2)

    // Net (vertical, dashed)
    ctx.strokeStyle = 'rgba(255,255,255,0.45)'
    ctx.lineWidth = 2.5
    ctx.setLineDash([8, 6])
    ctx.beginPath()
    ctx.moveTo(NET_X, TY)
    ctx.lineTo(NET_X, TY + TH)
    ctx.stroke()
    ctx.setLineDash([])

    // Net posts
    ctx.fillStyle = 'rgba(200,200,200,0.6)'
    ctx.fillRect(NET_X - 3, TY - 6, 6, 12)
    ctx.fillRect(NET_X - 3, TY + TH - 6, 6, 12)

    // Ball trail
    for (let i = 0; i < ball.trail.length; i++) {
      const t = ball.trail[i]
      const ratio = i / ball.trail.length
      ctx.fillStyle = `rgba(245, 245, 245, ${ratio * 0.25})`
      ctx.beginPath()
      ctx.arc(t.x, t.y, ball.radius * ratio * 0.9, 0, Math.PI * 2)
      ctx.fill()
    }

    // Ball
    if (gameState === 'playing' || gameState === 'gameover') {
      ctx.shadowColor = 'rgba(255,255,255,0.5)'
      ctx.shadowBlur = 14
      ctx.fillStyle = '#f5f5f5'
      ctx.beginPath()
      ctx.arc(ball.x, ball.y, ball.radius, 0, Math.PI * 2)
      ctx.fill()
      ctx.shadowColor = 'transparent'
      ctx.shadowBlur = 0

      // Highlight
      ctx.fillStyle = 'rgba(255,255,255,0.5)'
      ctx.beginPath()
      ctx.arc(ball.x - ball.radius * 0.3, ball.y - ball.radius * 0.3, ball.radius * 0.35, 0, Math.PI * 2)
      ctx.fill()

      // Serve pulse
      if (serveDelay > 0 && gameState === 'playing') {
        const pulse = Math.sin(Date.now() / 180) * 6 + 12
        ctx.strokeStyle = 'rgba(255,255,255,0.25)'
        ctx.lineWidth = 2
        ctx.beginPath()
        ctx.arc(ball.x, ball.y, ball.radius + pulse, 0, Math.PI * 2)
        ctx.stroke()

        // Countdown number
        const secs = Math.ceil(serveDelay / 60)
        ctx.font = 'bold 48px system-ui, sans-serif'
        ctx.textAlign = 'center'
        ctx.textBaseline = 'middle'
        ctx.fillStyle = 'rgba(255,255,255,0.6)'
        ctx.fillText(String(secs), CANVAS_W / 2, TY + 30)
      }
    }

    // Particles
    for (const p of particles) {
      ctx.globalAlpha = p.life / p.maxLife
      ctx.fillStyle = p.color
      ctx.beginPath()
      ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2)
      ctx.fill()
    }
    ctx.globalAlpha = 1

    // Paddles
    for (const p of paddles) {
      const color = p.team === 0 ? LEFT_COLOR : RIGHT_COLOR
      const cx = p.x + p.w / 2
      const cy = p.y + p.h / 2

      ctx.save()
      ctx.translate(cx, cy)
      ctx.scale(1, p.squash)

      ctx.shadowColor = color
      ctx.shadowBlur = 16
      ctx.fillStyle = color
      roundRect(-p.w / 2, -p.h / 2, p.w, p.h, 7)
      ctx.fill()
      ctx.shadowColor = 'transparent'
      ctx.shadowBlur = 0

      // Highlight stripe
      ctx.fillStyle = 'rgba(255,255,255,0.25)'
      roundRect(-p.w / 2 + 2, -p.h / 2 + 2, p.w - 4, 8, 3)
      ctx.fill()

      ctx.restore()
    }

    ctx.restore()
  }

  // ── Game loop ──────────────────────────────────────
  function gameLoop() {
    if (gameState === 'playing') update()
    draw()
    animationId = requestAnimationFrame(gameLoop)
  }

  // ── Input ──────────────────────────────────────────
  const PREVENT_KEYS = new Set([
    'arrowup', 'arrowdown', 'arrowleft', 'arrowright', ' ',
    'w', 'a', 's', 'd',
  ])

  function handleKeyDown(e: KeyboardEvent) {
    const key = e.key.toLowerCase()
    if (PREVENT_KEYS.has(key)) e.preventDefault()
    keys.add(key)
  }

  function handleKeyUp(e: KeyboardEvent) {
    keys.delete(e.key.toLowerCase())
  }

  function handleMouseMove(e: MouseEvent) {
    const rect = canvas.getBoundingClientRect()
    const scaleY = CANVAS_H / rect.height
    mouseY = (e.clientY - rect.top) * scaleY
    mouseInside = true
  }

  function handleMouseLeave() {
    mouseInside = false
  }

  // ── Lifecycle ──────────────────────────────────────
  function startGame() {
    initAudio()
    scores = [0, 0]
    rallyCount = 0
    winner = -1
    paddles = createPaddles()
    ball = createBall()
    particles = []
    servingDirection = Math.random() < 0.5 ? -1 : 1
    serveDelay = SERVE_DELAY_FRAMES
    savedProgress = null
    gameState = 'playing'
  }

  function resumeSaved() {
    if (!savedProgress) return
    initAudio()
    const saved = savedProgress
    scores = [saved.scores[0], saved.scores[1]]
    rallyCount = saved.rallyCount
    winner = saved.winner
    servingDirection = saved.servingDirection
    paddles = createPaddles()
    ball = createBall()
    particles = []
    serveDelay = SERVE_DELAY_FRAMES
    savedProgress = null
    gameState = 'playing'
  }

  function clearProgress() {
    clearSavedState()
    savedProgress = null
    scores = [0, 0]
    rallyCount = 0
    winner = -1
    gameState = 'menu'
  }

  onMount(() => {
    ctx = canvas.getContext('2d')!
    paddles = createPaddles()
    ball = createBall()

    // Restore saved state: always load settings, offer resume for in-progress games
    const saved = loadState()
    if (saved) {
      leftMouseMode = saved.leftMouseMode
      rightMouseMode = saved.rightMouseMode
      if (saved.gameState === 'playing' && (saved.scores[0] > 0 || saved.scores[1] > 0)) {
        savedProgress = saved
      } else if (saved.gameState === 'gameover') {
        scores = [saved.scores[0], saved.scores[1]]
        rallyCount = saved.rallyCount
        winner = saved.winner
        servingDirection = saved.servingDirection
        gameState = 'gameover'
      }
    }
    initialized = true

    window.addEventListener('keydown', handleKeyDown)
    window.addEventListener('keyup', handleKeyUp)
    window.addEventListener('beforeunload', saveState)
    canvas.addEventListener('mousemove', handleMouseMove)
    canvas.addEventListener('mouseleave', handleMouseLeave)
    gameLoop()

    return () => {
      cancelAnimationFrame(animationId)
      window.removeEventListener('keydown', handleKeyDown)
      window.removeEventListener('keyup', handleKeyUp)
      window.removeEventListener('beforeunload', saveState)
      canvas.removeEventListener('mousemove', handleMouseMove)
      canvas.removeEventListener('mouseleave', handleMouseLeave)
    }
  })
</script>

<div class="game-container">
  <header class="game-header">
    <h1 class="game-title">Table Tennis 1v1</h1>
    <div class="scoreboard">
      <div class="score-pill team-left" class:active={gameState === 'playing'}>
        <span class="team-label">Blue</span>
        <span class="score-num">{scores[0]}</span>
      </div>
      <div class="rally-display">
        <span class="rally-label">Rally</span>
        <span class="rally-num">{rallyCount}</span>
      </div>
      <div class="score-pill team-right" class:active={gameState === 'playing'}>
        <span class="score-num">{scores[1]}</span>
        <span class="team-label">Orange</span>
      </div>
    </div>
  </header>

  <div class="canvas-wrapper">
    <canvas
      bind:this={canvas}
      width={CANVAS_W}
      height={CANVAS_H}
      class="game-canvas"
    ></canvas>

    {#if gameState === 'menu'}
      <div class="overlay">
        <div class="overlay-card">
          <h2>One on One</h2>
          <p class="subtitle">First to {WINNING_SCORE} points wins</p>

          <div class="controls-grid">
            <div class="team-controls">
              <h3 class="team-heading left">Blue (Left)</h3>
              <div class="player-row">
                <span class="player-name">Move</span>
                <div class="keys">
                  <span class="key">W</span>
                  <span class="key">A</span>
                  <span class="key">S</span>
                  <span class="key">D</span>
                </div>
              </div>
              <label class="toggle-row">
                <input type="checkbox" bind:checked={leftMouseMode} />
                <span>Mouse control</span>
              </label>
            </div>
            <div class="team-controls">
              <h3 class="team-heading right">Orange (Right)</h3>
              <div class="player-row">
                <span class="player-name">Move</span>
                <div class="keys">
                  <span class="key">&#8593;</span>
                  <span class="key">&#8592;</span>
                  <span class="key">&#8595;</span>
                  <span class="key">&#8594;</span>
                </div>
              </div>
              <label class="toggle-row">
                <input type="checkbox" bind:checked={rightMouseMode} />
                <span>Mouse control</span>
              </label>
            </div>
          </div>

          <div class="rule-note">
            <strong>Tip:</strong> Move your paddle freely in your half. Hit the ball with the edge of your paddle to angle the shot. Your paddle's movement adds spin to the ball.
          </div>

          <button class="start-btn" onclick={startGame}>Start Match</button>
          {#if savedProgress}
            <button class="resume-btn" onclick={resumeSaved}>Resume Saved Match ({savedProgress.scores[0]}–{savedProgress.scores[1]})</button>
          {/if}
        </div>
      </div>
    {/if}

    {#if gameState === 'gameover'}
      <div class="overlay">
        <div class="overlay-card">
          <h2 class="winner-text" style="color: {winner === 0 ? LEFT_COLOR : RIGHT_COLOR}">
            {winner === 0 ? 'Blue' : 'Orange'} Wins!
          </h2>
          <p class="final-score">{scores[0]} &ndash; {scores[1]}</p>
          <button class="start-btn" onclick={startGame}>Play Again</button>
          <button class="resume-btn" onclick={clearProgress}>Clear Saved Progress</button>
        </div>
      </div>
    {/if}
  </div>

  <footer class="legend">
    <div class="legend-team left">
      <span class="legend-dot" style="background: {LEFT_COLOR}"></span>
      <span class="legend-labels">
        {leftMouseMode ? 'Mouse' : 'W A S D'}
      </span>
    </div>
    <div class="legend-team right">
      <span class="legend-labels">
        {rightMouseMode ? 'Mouse' : '&#8593; &#8592; &#8595; &#8594;'}
      </span>
      <span class="legend-dot" style="background: {RIGHT_COLOR}"></span>
    </div>
  </footer>
</div>

<style>
  .game-container {
    max-width: 940px;
    margin: 0 auto;
    padding: 20px 16px 32px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .game-header {
    display: flex;
    flex-direction: column;
    gap: 14px;
    align-items: center;
  }

  .game-title {
    margin: 0;
    font-size: 30px;
    font-weight: 700;
    color: #e8eaf0;
    letter-spacing: -0.5px;
  }

  .scoreboard {
    display: flex;
    align-items: center;
    gap: 16px;
    width: 100%;
    justify-content: center;
  }

  .score-pill {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 20px;
    border-radius: 12px;
    background: rgba(255, 255, 255, 0.04);
    border: 2px solid transparent;
    transition: border-color 0.3s;
  }

  .score-pill.team-left { border-color: rgba(59, 180, 247, 0.15); }
  .score-pill.team-right { border-color: rgba(255, 120, 73, 0.15); }
  .score-pill.active.team-left { border-color: rgba(59, 180, 247, 0.5); }
  .score-pill.active.team-right { border-color: rgba(255, 120, 73, 0.5); }

  .team-label {
    font-size: 14px;
    color: #9ca3af;
    font-weight: 500;
  }

  .score-num {
    font-size: 28px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .team-left .score-num { color: #3bb4f7; }
  .team-right .score-num { color: #ff7849; }

  .rally-display {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 2px;
  }

  .rally-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: #6b7280;
  }

  .rally-num {
    font-size: 20px;
    font-weight: 600;
    color: #d1d5db;
    font-variant-numeric: tabular-nums;
  }

  .canvas-wrapper {
    position: relative;
    width: 100%;
    aspect-ratio: 3 / 2;
    border-radius: 14px;
    overflow: hidden;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  }

  .game-canvas {
    display: block;
    width: 100%;
    height: 100%;
  }

  .overlay {
    position: absolute;
    inset: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(10, 11, 20, 0.82);
    backdrop-filter: blur(6px);
    padding: 20px;
  }

  .overlay-card {
    text-align: center;
    max-width: 520px;
    width: 100%;
  }

  .overlay-card h2 {
    margin: 0 0 6px;
    font-size: 32px;
    color: #e8eaf0;
    font-weight: 700;
  }

  .subtitle {
    color: #9ca3af;
    font-size: 16px;
    margin: 0 0 24px;
  }

  .winner-text {
    font-size: 40px !important;
    font-weight: 800 !important;
    margin: 0 0 8px !important;
  }

  .final-score {
    font-size: 28px;
    color: #d1d5db;
    font-weight: 600;
    margin: 0 0 28px;
    font-variant-numeric: tabular-nums;
  }

  .controls-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 24px;
    margin-bottom: 20px;
  }

  @media (max-width: 560px) {
    .controls-grid { grid-template-columns: 1fr; }
  }

  .team-controls {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 10px;
  }

  .team-heading {
    font-size: 15px;
    font-weight: 600;
    margin: 0;
  }

  .team-heading.left { color: #3bb4f7; }
  .team-heading.right { color: #ff784f; }

  .player-row {
    display: flex;
    align-items: center;
    gap: 10px;
  }

  .player-name {
    font-size: 13px;
    color: #9ca3af;
    font-weight: 600;
    min-width: 40px;
    text-align: right;
  }

  .keys {
    display: flex;
    gap: 4px;
  }

  .key {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 26px;
    height: 26px;
    padding: 0 5px;
    border-radius: 5px;
    background: rgba(255, 255, 255, 0.08);
    border: 1px solid rgba(255, 255, 255, 0.15);
    font-size: 13px;
    font-family: ui-monospace, monospace;
    color: #d1d5db;
  }

  .toggle-row {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
    color: #9ca3af;
    cursor: pointer;
  }

  .toggle-row input {
    cursor: pointer;
    accent-color: #3bb4f7;
  }

  .rule-note {
    font-size: 13px;
    color: #9ca3af;
    line-height: 1.5;
    padding: 12px 16px;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.04);
    margin-bottom: 24px;
  }

  .rule-note strong { color: #d1d5db; }

  .start-btn {
    padding: 14px 40px;
    font-size: 18px;
    font-weight: 600;
    color: #fff;
    background: linear-gradient(135deg, #3bb4f7, #2563eb);
    border: none;
    border-radius: 10px;
    cursor: pointer;
    transition: transform 0.15s, box-shadow 0.2s;
    box-shadow: 0 4px 20px rgba(59, 180, 247, 0.3);
  }

  .start-btn:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 28px rgba(59, 180, 247, 0.45);
  }

  .start-btn:active { transform: translateY(0); }

  .resume-btn {
    display: block;
    margin: 14px auto 0;
    padding: 10px 28px;
    font-size: 15px;
    font-weight: 500;
    color: #9ca3af;
    background: transparent;
    border: 1px solid rgba(255, 255, 255, 0.15);
    border-radius: 10px;
    cursor: pointer;
    transition: border-color 0.2s, color 0.2s;
  }

  .resume-btn:hover {
    border-color: rgba(59, 180, 247, 0.4);
    color: #d1d5db;
  }

  .legend {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 20px;
    border-radius: 10px;
    background: rgba(255, 255, 255, 0.03);
    flex-wrap: wrap;
    gap: 12px;
  }

  .legend-team {
    display: flex;
    align-items: center;
    gap: 8px;
  }

  .legend-dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    flex-shrink: 0;
  }

  .legend-labels {
    font-size: 13px;
    color: #9ca3af;
    font-family: ui-monospace, monospace;
  }
</style>
