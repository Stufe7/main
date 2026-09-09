<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	const activityId = $derived($page.params.id);
	let activity = $state<Record<string, string | null> | null>(null);
	let revisions = $state<Record<string, string | number | null>[]>([]);
	let error = $state('');
	let subject = $state('');
	let description = $state('');
	let outcome = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			const data = await api<{
				activity: Record<string, string | null>;
				revisions: Record<string, string | number | null>[];
			}>(`/v1/activities/${activityId}`);
			activity = data.activity;
			revisions = data.revisions;
			subject = String(activity.subject || '');
			description = String(activity.description || '');
			outcome = String(activity.outcome || '');
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load activity.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		if (!activity) return;
		error = '';
		try {
			const updated = await api<Record<string, string | null>>(`/v1/activities/${activityId}`, {
				method: 'PATCH',
				body: JSON.stringify({
					company_id: activity.company_id,
					contact_id: activity.contact_id,
					activity_type: activity.activity_type,
					subject,
					description,
					outcome
				})
			});
			activity = updated;
			const data = await api<{ revisions: Record<string, string | number | null>[] }>(
				`/v1/activities/${activityId}`
			);
			revisions = data.revisions;
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		}
	}
</script>

<svelte:head>
	<title>Activity — Stufe7</title>
</svelte:head>

<section class="card">
	<p><a href="/app">← Home</a></p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if activity}
		<p>{activity.company_name} · {activity.activity_type}</p>
		<form onsubmit={save}>
			<label>Subject <input bind:value={subject} required /></label>
			<label>Description <textarea bind:value={description} rows="4"></textarea></label>
			<label>Outcome <input bind:value={outcome} /></label>
			<button type="submit">Save</button>
		</form>
		<h2>Revisions</h2>
		<ul>
			{#each revisions as rev (rev.revision_number)}
				<li>{rev.edited_at} · {rev.subject}</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.card {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	form,
	label {
		display: grid;
		gap: 0.35rem;
	}
	input,
	textarea,
	button {
		font: inherit;
	}
	input,
	textarea {
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
		padding: 0.6rem 1rem;
		width: fit-content;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
	a {
		color: #20265e;
	}
</style>
