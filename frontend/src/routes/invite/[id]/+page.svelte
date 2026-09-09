<script lang="ts">
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { setActiveEntityId } from '$lib/entity';

	const invitationId = $derived(page.params.id);
	let error = $state('');
	let busy = $state(false);

	onMount(async () => {
		if (!(await requireSession())) {
			error = 'Log in with the invited work email, then open this invitation link again.';
		}
	});

	async function accept() {
		busy = true;
		error = '';
		try {
			const result = await api<{ entity_id: string }>(`/v1/invitations/${invitationId}/accept`, {
				method: 'POST'
			});
			setActiveEntityId(result.entity_id);
			await goto('/app/companies');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Invitation cannot be accepted.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>Accept invitation — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>Join workspace</h1>
	{#if error}
		<p class="error">{error}</p>
		<p><a href="/">Log in</a></p>
	{:else}
		<p>Continue to join the entity you were invited to.</p>
		<button type="button" disabled={busy} onclick={accept}>Accept invitation</button>
	{/if}
</section>

<style>
	.card {
		width: min(28rem, calc(100% - 2rem));
		margin: 3rem auto;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font: inherit;
		font-weight: 650;
		padding: 0.7rem 1rem;
		cursor: pointer;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
