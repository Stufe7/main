<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	const hours = Array.from({ length: 24 }, (_, hour) => `${String(hour).padStart(2, '0')}:00:00`);

	let digestTime = $state('08:00:00');
	let error = $state('');
	let info = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		const role = session.memberships.find(
			(row) => row.entity_id === ensureActiveEntity(session.memberships)
		)?.role;
		if (role !== 'Entity Admin') {
			error = 'Entity Admin access is required.';
			return;
		}
		try {
			const settings = await api<{ digest_send_local_time: string }>('/v1/settings/entity');
			digestTime = settings.digest_send_local_time.slice(0, 8);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load entity settings.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/settings/entity', {
				method: 'PATCH',
				body: JSON.stringify({ digest_send_local_time: digestTime })
			});
			info = 'General settings saved.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		}
	}
</script>

<svelte:head>
	<title>Entity general — Stufe7</title>
</svelte:head>

<section class="wrap">
	<h1>General</h1>
	<p>
		Whole-hour digest send time for this entity. Each member receives it in their own timezone. Cadence
		and timezone are per person under Digest.
	</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form onsubmit={save}>
		<label>Digest send time
			<select bind:value={digestTime}>
				{#each hours as hour (hour)}
					<option value={hour}>{hour.slice(0, 5)}</option>
				{/each}
			</select>
		</label>
		<button type="submit">Save</button>
	</form>
</section>

<style>
	.wrap,
	form,
	label {
		display: grid;
		gap: 0.5rem;
	}
	.wrap {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	form {
		background: white;
		border-radius: 1rem;
		padding: 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	select,
	button {
		font: inherit;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.4rem 0.55rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.45rem 0.9rem;
		width: fit-content;
		cursor: pointer;
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
