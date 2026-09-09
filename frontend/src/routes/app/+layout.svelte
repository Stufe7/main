<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';
	import { ENTITY_KEY, activeEntityId, setActiveEntityId } from '$lib/entity';

	let { children } = $props();
	let session = $state<SessionInfo | null>(null);
	let currentEntity = $state('');
	const currentRole = $derived(
		session?.memberships.find((row) => row.entity_id === currentEntity)?.role || ''
	);

	onMount(async () => {
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
			<a href="/app/invite">Invite</a>
			{#if currentRole === 'Entity Admin'}
				<a href="/app/settings/users">Users</a>
			{/if}
			<a href="/app/settings/domains">Domains</a>
			<a href="/app/entities/new">New entity</a>
			{#if session?.platform_admin}
				<a href="/platform/approvals">Approvals</a>
			{/if}
		</nav>
		{#if session && session.memberships.length > 1}
			<select value={currentEntity} onchange={(event) => switchEntity(event.currentTarget.value)}>
				{#each session.memberships as membership (membership.entity_id)}
					<option value={membership.entity_id}>{membership.entity_name}</option>
				{/each}
			</select>
		{/if}
		{#if auth.email}
			<span class="who">{auth.email}</span>
			<button type="button" onclick={leave}>Sign out</button>
		{/if}
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
	nav a,
	button {
		color: #20265e;
		font-weight: 650;
		text-decoration: none;
		background: none;
		border: 0;
		cursor: pointer;
		font: inherit;
	}
	.who {
		margin-left: auto;
		color: #5b607a;
		font-size: 0.9rem;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.35rem 0.5rem;
		font: inherit;
	}
</style>
