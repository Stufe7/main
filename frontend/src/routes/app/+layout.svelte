<script lang="ts">
	import { afterNavigate, goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';
	import { ENTITY_KEY, activeEntityId, setActiveEntityId } from '$lib/entity';

	let { children } = $props();
	let session = $state<SessionInfo | null>(null);
	let currentEntity = $state('');
	let menu = $state<HTMLDetailsElement | null>(null);

	onMount(() => {
		function onDocClick(event: MouseEvent) {
			if (!menu?.open) return;
			if (menu.contains(event.target as Node)) return;
			menu.open = false;
		}
		function onDocKey(event: KeyboardEvent) {
			if (event.key === 'Escape' && menu) menu.open = false;
		}
		document.addEventListener('click', onDocClick);
		document.addEventListener('keydown', onDocKey);

		void (async () => {
			const email = await requireSession();
			if (!email) {
				await goto('/');
				return;
			}
			try {
				session = await api<SessionInfo>('/v1/session');
			} catch {
				return;
			}
			if (!session.memberships.length && session.pending_registration) {
				await goto('/signup/pending');
				return;
			}
			const stored = activeEntityId();
			const match = session.memberships.find((row) => row.entity_id === stored);
			currentEntity = match?.entity_id || session.memberships[0]?.entity_id || '';
			if (currentEntity) setActiveEntityId(currentEntity);
		})();

		return () => {
			document.removeEventListener('click', onDocClick);
			document.removeEventListener('keydown', onDocKey);
		};
	});

	afterNavigate(() => {
		if (menu) menu.open = false;
	});

	async function leave() {
		localStorage.removeItem(ENTITY_KEY);
		await signOut();
		await goto('/');
	}

	function switchEntity(entityId: string) {
		setActiveEntityId(entityId);
		currentEntity = entityId;
		location.assign('/app/companies');
	}
</script>

<div class="shell">
	<header>
		<a href="/app" class="brand"><img src="/stufe7-logo.svg" alt="Stufe7" /></a>
		<nav>
			<a href="/app">Home</a>
			<a href="/app/companies">Companies</a>
			<a href="/app/contacts">Contacts</a>
			<a href="/app/activities">Activities</a>
			<a href="/app/campaigns">Campaigns</a>
			{#if session?.platform_admin}
				<a href="/platform/approvals">Approvals</a>
			{/if}
			{#if session?.privacy_operator}
				<a href="/platform/privacy">Privacy</a>
			{/if}
		</nav>
		<div class="end">
			{#if session && session.memberships.length > 1}
				<select value={currentEntity} onchange={(event) => switchEntity(event.currentTarget.value)}>
					{#each session.memberships as membership (membership.entity_id)}
						<option value={membership.entity_id}>{membership.entity_name}</option>
					{/each}
				</select>
			{/if}
			{#if auth.email}
				<details class="account" bind:this={menu}>
					<summary>{auth.email}</summary>
					<div class="menu">
						<a href="/app/settings">Settings</a>
						<a href="/app/invite">Invite</a>
						<a href="/app/entities/new">New entity</a>
						<button type="button" onclick={leave}>Sign out</button>
					</div>
				</details>
			{/if}
		</div>
	</header>
	{@render children()}
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
		flex-wrap: wrap;
		gap: 0.75rem;
	}
	nav a {
		color: #20265e;
		font-weight: 650;
		text-decoration: none;
	}
	.end {
		margin-left: auto;
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}
	.account {
		position: relative;
	}
	.account summary {
		list-style: none;
		cursor: pointer;
		color: #5b607a;
		font-size: 0.9rem;
		font-weight: 650;
	}
	.account summary::-webkit-details-marker {
		display: none;
	}
	.account summary::after {
		content: '▾';
		margin-left: 0.35rem;
		font-size: 0.75rem;
	}
	.menu {
		position: absolute;
		right: 0;
		top: calc(100% + 0.45rem);
		z-index: 20;
		min-width: 12.5rem;
		display: grid;
		padding: 0.35rem;
		background: white;
		border: 1px solid #e6e8f2;
		border-radius: 0.75rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.08);
	}
	.menu a,
	.menu button {
		display: block;
		width: 100%;
		padding: 0.55rem 0.75rem;
		border: 0;
		border-radius: 0.5rem;
		background: none;
		color: #20265e;
		font: inherit;
		font-weight: 650;
		text-align: left;
		text-decoration: none;
		cursor: pointer;
	}
	.menu a:hover,
	.menu button:hover {
		background: #f6f7fb;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.35rem 0.5rem;
		font: inherit;
	}
</style>
