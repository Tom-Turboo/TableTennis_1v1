import { svelte } from '@sveltejs/vite-plugin-svelte'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [svelte()],
  // GitHub Pages serves at /repo-name/, so the base path must match.
  // On GitHub Actions, GITHUB_REPOSITORY is "owner/repo-name".
  // Locally (npm run dev / npm run build) it falls back to '/'.
  base: process.env.GITHUB_REPOSITORY
    ? '/' + process.env.GITHUB_REPOSITORY.split('/')[1] + '/'
    : '/',
})
