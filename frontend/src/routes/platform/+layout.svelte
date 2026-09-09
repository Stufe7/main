<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { api, type SessionInfo } from '$lib/api/client';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';

	let { children } = $props();
	let session = $state<SessionInfo | null>(null);
	let error = $state('');
	const path = $derived(page.url.pathname);

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			session = await api<SessionInfo>('/v1/session');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load session.';
			return;
		}
		if (!session.platform_admin && !session.privacy_operator) {
			error = 'This login is not a platform operator.';
			return;
		}
		if (path === '/platform' || path === '/platform/') {
			await goto(session.platform_admin ? '/platform/approvals' : '/platform/privacy');
		}
	});

	async function leave() {
		await signOut();
		await goto('/');
	}
</script>

<div class="shell">
	<header>
		<a href="/platform" class="brand"><img src="/stufe7-logo.svg" alt="Stufe7 Admin" /></a>
		<nav aria-label="Admin">
			{#if session?.platform_admin}
				<a href="/platform/approvals" class:on={path.startsWith('/platform/approvals')}>Approvals</a>
			{/if}
			{#if session?.privacy_operator}
				<a href="/platform/privacy" class:on={path.startsWith('/platform/privacy')}>Privacy</a>
			{/if}
		</nav>
		<div class="end">
			{#if auth.email}
				<span class="who">{auth.email}</span>
				<button type="button" onclick={leave}>Sign out</button>
			{/if}
		</div>
	</header>
	{#if error}
		<p class="error">{error}</p>
	{:else}
		{@render children()}
	{/if}
</div>

<style>
	.shell {
		min-height: 100vh;
	}
	header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.75rem 1rem;
		padding: 1rem 1.25rem;
		background: white;
		border-bottom: 1px solid #e6e8f2;
	}
	.brand img {
		height: 1.6rem;
		width: auto;
	}
	nav {
		display: flex;
		gap: 0.75rem;
	}
	nav a {
		color: #5b607a;
		font-weight: 650;
		text-decoration: none;
		padding: 0.15rem 0;
	}
	nav a.on {
		color: #20265e;
		box-shadow: 0 2px 0 #20265e;
	}
	.end {
		margin-left: auto;
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}
	.who {
		color: #5b607a;
		font-size: 0.9rem;
	}
	button {
		border: 0;
		background: none;
		color: #20265e;
		font: inherit;
		font-weight: 650;
		cursor: pointer;
	}
	.error {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto;
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.75rem 1rem;
		border-radius: 0.6rem;
	}
</style>
