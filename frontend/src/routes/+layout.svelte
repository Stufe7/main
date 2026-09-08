<script lang="ts">
	import { onMount } from 'svelte';
	import { startAuthListener } from '$lib/auth/session.svelte';
	import './layout.css';
	let { children } = $props();

	onMount(startAuthListener);
</script>

<svelte:head>
	<link rel="icon" href="/favicon.ico" sizes="any" />
	<link rel="icon" href="/favicon.svg" type="image/svg+xml" />
	<link rel="apple-touch-icon" href="/apple-touch-icon.png" />
	<link rel="manifest" href="/site.webmanifest" />
	<meta name="theme-color" content="#20265E" />
</svelte:head>

{@render children()}
