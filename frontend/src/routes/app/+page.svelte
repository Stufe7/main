<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { auth, requireSession, signOut } from '$lib/auth/session.svelte';

	const ENTITY_KEY = 'stufe7.active_entity_id';

	let session = $state<SessionInfo | null>(null);
	let error = $state('');
	let activeEntity = $state('');

	onMount(async () => {
		const email = await requireSession();
		if (!email) {
			await goto('/');
			return;
		}
		try {
			session = await api<SessionInfo>('/v1/session');
			if (!session.memberships.length && session.pending_registration) {
				await goto('/signup/pending');
				return;
			}
			const stored = localStorage.getItem(ENTITY_KEY);
			const match = session.memberships.find((row) => row.entity_id === stored);
			activeEntity = match?.entity_id || session.memberships[0]?.entity_id || '';
			if (activeEntity) localStorage.setItem(ENTITY_KEY, activeEntity);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load session.';
		}
	});

	function switchEntity(entityId: string) {
		activeEntity = entityId;
		localStorage.setItem(ENTITY_KEY, entityId);
	}

	async function leave() {
		localStorage.removeItem(ENTITY_KEY);
		await signOut();
		await goto('/');
	}

	const current = $derived(session?.memberships.find((row) => row.entity_id === activeEntity));
</script>

<svelte:head>
	<title>Home — Stufe7</title>
</svelte:head>

<div class="page">
	<header>
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
		{#if auth.email}
			<p class="who">{auth.email}</p>
			{#if session?.platform_admin}
				<a href="/platform/approvals">Approvals</a>
			{/if}
			<button type="button" class="ghost" onclick={leave}>Sign out</button>
		{/if}
	</header>

	{#if error}
		<p class="error">{error}</p>
	{:else if session && current}
		<section class="card">
			<h1>{current.entity_name}</h1>
			<p>You are signed in as {current.role}. The CRM workspace is next.</p>
			{#if session.memberships.length > 1}
				<label>
					Active entity
					<select
						value={activeEntity}
						onchange={(event) => switchEntity(event.currentTarget.value)}
					>
						{#each session.memberships as membership (membership.entity_id)}
							<option value={membership.entity_id}>{membership.entity_name}</option>
						{/each}
					</select>
				</label>
			{/if}
		</section>
	{:else if session}
		<section class="card">
			<h1>No company access</h1>
			<p>This login has no active entity membership yet.</p>
		</section>
	{/if}
</div>

<style>
	.page {
		min-height: 100vh;
		padding: 1.25rem 1rem 3rem;
	}
	header,
	.card {
		width: min(40rem, 100%);
		margin-inline: auto;
	}
	header {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.75rem 1rem;
		margin-bottom: 1.5rem;
	}
	.wordmark {
		height: 1.75rem;
		width: auto;
	}
	.who {
		margin: 0 auto 0 0;
		color: #5b607a;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1 {
		margin: 0 0 0.75rem;
		font-size: 1.5rem;
	}
	p {
		margin: 0 0 1rem;
		color: #3c4160;
	}
	select {
		margin-top: 0.35rem;
		display: block;
		width: 100%;
		padding: 0.6rem 0.75rem;
		border: 1px solid #d5d8e6;
		border-radius: 0.6rem;
		font: inherit;
	}
	.ghost,
	a {
		border: 1px solid #20265e;
		background: white;
		color: #20265e;
		border-radius: 999px;
		padding: 0.45rem 0.9rem;
		font: inherit;
		font-weight: 650;
		text-decoration: none;
	}
	.ghost {
		cursor: pointer;
	}
	.error {
		width: min(40rem, 100%);
		margin: 0 auto 1rem;
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem 0.75rem;
		border-radius: 0.6rem;
	}
</style>
