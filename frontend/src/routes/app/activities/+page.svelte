<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, withActiveEntity, type Activity } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	let rows = $state<Activity[]>([]);
	let error = $state('');

	async function load() {
		rows = await api<Activity[]>('/v1/activities');
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			await withActiveEntity(load);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load activities.';
		}
	});
</script>

<svelte:head>
	<title>Activities — Stufe7</title>
</svelte:head>

<section class="wrap">
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<ul class="list">
		{#each rows as row (row.id)}
			<li>
				<a href={`/app/activities/${row.id}`}>
					<strong>{row.subject}</strong>
					<span>{row.company_name} · {row.activity_type} · {row.activity_date.slice(0, 10)}</span>
				</a>
			</li>
		{/each}
	</ul>
	{#if !error && !rows.length}
		<p>No activities yet.</p>
	{/if}
</section>

<style>
	.wrap {
		width: min(52rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
		background: white;
		border-radius: 1rem;
		overflow: hidden;
	}
	li a {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		padding: 0.85rem 1rem;
		border-bottom: 1px solid #eef0f6;
		color: inherit;
		text-decoration: none;
	}
	span {
		color: #5b607a;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
