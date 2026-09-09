<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type HomeInfo, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	let home = $state<HomeInfo | null>(null);
	let horizon = $state('today');
	let scope = $state('my');
	let error = $state('');
	let completeId = $state('');
	let selected = $state<string[]>([]);
	let outcome = $state('');
	let nextDue = $state('');
	let nextDesc = $state('');

	async function load() {
		error = '';
		try {
			const session = await api<SessionInfo>('/v1/session');
			if (!ensureActiveEntity(session.memberships)) {
				error = 'No entity membership.';
				return;
			}
			home = await api<HomeInfo>(`/v1/home?horizon=${horizon}&scope=${scope}`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load home.';
		}
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		await load();
	});

	async function ack(id: string) {
		await api(`/v1/handovers/${id}/ack`, { method: 'POST' });
		await load();
	}

	async function ackAll() {
		await api('/v1/handovers/ack-all', { method: 'POST' });
		selected = [];
		await load();
	}

	async function ackSelected() {
		await api('/v1/handovers/ack-selected', {
			method: 'POST',
			body: JSON.stringify({ ids: selected })
		});
		selected = [];
		await load();
	}

	async function complete(event: Event) {
		event.preventDefault();
		error = '';
		try {
			const body: Record<string, unknown> = {
				activity_type: 'Note',
				subject: 'Completed action',
				outcome
			};
			if (nextDue && nextDesc) {
				body.follow_up = {
					action_type: 'Task',
					description: nextDesc,
					due_date: nextDue,
					priority: 'Normal'
				};
			}
			await api(`/v1/actions/${completeId}/complete`, {
				method: 'POST',
				body: JSON.stringify(body)
			});
			completeId = '';
			outcome = '';
			nextDue = '';
			nextDesc = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Complete failed.';
		}
	}
</script>

<svelte:head>
	<title>Home — Stufe7</title>
</svelte:head>

<section class="wrap">
	<div class="toolbar">
		<h1>Work queue</h1>
		<select bind:value={horizon} onchange={() => load()}>
			<option value="overdue">Overdue</option>
			<option value="today">Today</option>
			<option value="week">This week</option>
			<option value="open">All open</option>
		</select>
		<select bind:value={scope} onchange={() => load()}>
			<option value="my">My actions</option>
			<option value="team">Team</option>
		</select>
	</div>
	{#if home}
		<p class="meta">
			{home.today} · {home.timezone}
			{#if home.attention_count}
				· {home.attention_count} companies overdue
			{/if}
		</p>
	{/if}
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if home?.handovers.length}
		<section class="card">
			<h2>Handovers</h2>
			<button type="button" class="ghost" onclick={ackSelected} disabled={!selected.length}>
				Review selected
			</button>
			<button type="button" class="ghost" onclick={ackAll}>Review all</button>
			{#each home.handovers as row (row.id)}
				<p>
					<label>
						<input type="checkbox" bind:group={selected} value={row.id} />
						<a href={`/app/companies/${row.company_id}`}>{row.company_name}</a>
						{row.reason}
					</label>
					<button type="button" onclick={() => ack(row.id)}>Review</button>
				</p>
			{/each}
		</section>
	{/if}
	{#if home && !home.actions.length}
		<p>No actions in this view.</p>
	{/if}
	<ul class="list">
		{#each home?.actions || [] as row (row.id)}
			<li class="card">
				<p class="pri">{row.priority}</p>
				<a href={`/app/companies/${row.company_id}`}>{row.company_name}</a>
				<p>{row.action_type}: {row.description}</p>
				<p class="meta">{row.due_date}{row.due_time ? ` ${row.due_time}` : ''}</p>
				<button type="button" onclick={() => (completeId = row.id)}>Complete</button>
				{#if completeId === row.id}
					<form onsubmit={complete}>
						<label>Outcome <input bind:value={outcome} required /></label>
						<label>Next action <input bind:value={nextDesc} placeholder="Follow-up" /></label>
						<label>Due <input type="date" bind:value={nextDue} /></label>
						<button type="submit">Save</button>
					</form>
				{/if}
			</li>
		{/each}
	</ul>
</section>

<style>
	.wrap {
		width: min(44rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	.toolbar {
		display: flex;
		flex-wrap: wrap;
		gap: 0.6rem;
		align-items: center;
	}
	h1 {
		margin: 0 auto 0 0;
	}
	.list {
		list-style: none;
		padding: 0;
		display: grid;
		gap: 0.75rem;
	}
	.card,
	form {
		background: white;
		border-radius: 1rem;
		padding: 1rem 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	.pri {
		font-size: 0.75rem;
		font-weight: 700;
		color: #8a1f1f;
	}
	.meta {
		color: #5b607a;
		font-size: 0.9rem;
	}
	form,
	label {
		display: grid;
		gap: 0.35rem;
		margin-top: 0.5rem;
	}
	input,
	select,
	button {
		font: inherit;
	}
	input,
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.45rem 0.6rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.45rem 0.85rem;
		cursor: pointer;
		width: fit-content;
	}
	.ghost {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
	a {
		color: #20265e;
		font-weight: 650;
	}
</style>
