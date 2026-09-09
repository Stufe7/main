<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	let name = $state('');
	let description = $state('');
	let startDate = $state('');
	let endDate = $state('');
	let status = $state('Planned');
	let error = $state('');
	let info = $state('');
	let busy = $state(false);

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		ensureActiveEntity(session.memberships);
	});

	async function submit(event: Event) {
		event.preventDefault();
		if (busy) return;
		error = '';
		info = '';
		busy = true;
		try {
			const created = await api<{ id: string }>('/v1/campaigns', {
				method: 'POST',
				body: JSON.stringify({
					name,
					description: description || null,
					start_date: startDate,
					end_date: endDate,
					status
				})
			});
			info = 'Campaign saved.';
			await goto(`/app/campaigns/${created.id}?saved=1`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>New campaign — Stufe7</title>
</svelte:head>

<section class="card">
	<h1>New campaign</h1>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form onsubmit={submit}>
		<label>Name <input bind:value={name} required disabled={busy} /></label>
		<label>Description <textarea bind:value={description} disabled={busy}></textarea></label>
		<label>Start <input type="date" bind:value={startDate} required disabled={busy} /></label>
		<label>End <input type="date" bind:value={endDate} required disabled={busy} /></label>
		<label>Status
			<select bind:value={status} disabled={busy}>
				<option>Planned</option>
				<option>Active</option>
			</select>
		</label>
		<button type="submit" disabled={busy}>{busy ? 'Saving…' : 'Save campaign'}</button>
	</form>
</section>

<style>
	.card {
		width: min(36rem, calc(100% - 2rem));
		margin: 1.5rem auto;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	form,
	label {
		display: grid;
		gap: 0.4rem;
	}
	input,
	textarea,
	select,
	button {
		font: inherit;
	}
	input,
	textarea,
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.7rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.7rem 1rem;
	}
	button:disabled {
		opacity: 0.7;
		cursor: wait;
	}
	.error,
	.info {
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
	}
	.info {
		background: #eef7f1;
		color: #1e5c3a;
	}
</style>
