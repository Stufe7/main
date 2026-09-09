<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, withActiveEntity } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Campaign = {
		id: string;
		name: string;
		description: string | null;
		owner_user_id: string;
		start_date: string;
		end_date: string;
		status: string;
		record_state: string;
		company_count: number;
	};

	let rows = $state<Campaign[]>([]);
	let error = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			rows = await withActiveEntity(() => api<Campaign[]>('/v1/campaigns'));
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load campaigns.';
		}
	});
</script>

<svelte:head>
	<title>Campaigns — Stufe7</title>
</svelte:head>

<section class="wrap">
	<div class="toolbar">
		<a href="/app/campaigns/new">Add campaign</a>
	</div>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	<ul class="list">
		{#each rows as row (row.id)}
			<li>
				<a href={`/app/campaigns/${row.id}`}>
					<strong>{row.name}</strong>
					<span>{row.company_count} companies · {row.status} · {row.start_date} – {row.end_date}</span>
				</a>
			</li>
		{/each}
	</ul>
	{#if !error && !rows.length}
		<p>No campaigns yet.</p>
	{/if}
</section>

<style>
	.wrap {
		width: min(52rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	.toolbar {
		display: flex;
		align-items: center;
		justify-content: flex-end;
		gap: 0.75rem;
		margin-bottom: 1rem;
	}
	.toolbar a {
		font: inherit;
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.5rem 0.9rem;
		text-decoration: none;
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
