import tailwindcss from '@tailwindcss/vite';
import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [
		tailwindcss(),
		sveltekit({
			compilerOptions: {
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: adapter(),
			csp: {
				mode: 'auto',
				directives: {
					'default-src': ['self'],
					'script-src': ['self'],
					'style-src': ['self', 'unsafe-inline'],
					'img-src': ['self', 'data:'],
					'font-src': ['self'],
					'connect-src': [
						'self',
						'https://*.supabase.co',
						'wss://*.supabase.co',
						'https://stufe7-api.onrender.com',
						'http://127.0.0.1:8000',
						'http://localhost:8000'
					],
					'frame-ancestors': ['none'],
					'base-uri': ['self'],
					'form-action': ['self']
				}
			}
		})
	]
});
