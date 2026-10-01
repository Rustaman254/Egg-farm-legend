import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  server: {
    port: 5173,
    // Allow access via an ngrok tunnel (e.g. for testing on a phone) -- wildcard the two ngrok
    // domains so this keeps working across tunnel restarts, which issue a new random subdomain
    // every time on the free tier.
    allowedHosts: ['.ngrok-free.dev', '.ngrok-free.app', '.ngrok.io'],
  },
})
