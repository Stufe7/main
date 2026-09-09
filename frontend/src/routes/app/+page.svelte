<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { activeEntityId } from '$lib/entity';

	let session = $state<SessionInfo | null>(null);
	let name = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		session = await api<SessionInfo>('/v1/session');
		const id = activeEntityId();
		name = session.memberships.find((row) => row.entity_id === id)?.entity_name || session.memberships[0]?.entity_name || '';
	});
</script>

<svelte:head>
	<title>Home — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>{name || 'Workspace'}</h1>
	<p>Open the company list to work accounts. Invite colleagues and add email domains from the header.</p>
	<p><a href="/app/companies">Go to companies</a></p>
</section>

<style>
	.card {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	h1 {
		margin: 0 0 0.75rem;
	}
	a {
		color: #20265e;
		font-weight: 650;
	}
</style>
