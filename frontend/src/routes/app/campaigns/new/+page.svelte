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
		error = '';
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
			await goto(`/app/campaigns/${created.id}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
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
	<form onsubmit={submit}>
		<label>Name <input bind:value={name} required /></label>
		<label>Description <textarea bind:value={description}></textarea></label>
		<label>Start <input type="date" bind:value={startDate} required /></label>
		<label>End <input type="date" bind:value={endDate} required /></label>
		<label>Status
			<select bind:value={status}>
				<option>Planned</option>
				<option>Active</option>
			</select>
		</label>
		<button type="submit">Create</button>
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
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
