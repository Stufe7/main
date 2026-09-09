<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { api, withActiveEntity, type ActionItem, type Activity, type Contact } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	const contactId = $derived(page.params.id);
	let row = $state<Contact | null>(null);
	let activities = $state<Activity[]>([]);
	let actions = $state<ActionItem[]>([]);
	let error = $state('');
	let subject = $state('');
	let nextDue = $state('');
	let nextDesc = $state('');

	async function load() {
		[row, activities, actions] = await Promise.all([
			api<Contact>(`/v1/contacts/${contactId}`),
			api<Activity[]>(`/v1/activities?contact_id=${contactId}`),
			api<ActionItem[]>(`/v1/actions?contact_id=${contactId}&horizon=open&scope=team`)
		]);
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			await withActiveEntity(load);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load contact.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		if (!row) return;
		error = '';
		try {
			row = await api<Contact>(`/v1/contacts/${contactId}`, {
				method: 'PATCH',
				body: JSON.stringify(row)
			});
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		}
	}

	async function archive() {
		if (!row) return;
		error = '';
		try {
			row = await api<Contact>(`/v1/contacts/${contactId}`, {
				method: 'PATCH',
				body: JSON.stringify({
					...row,
					record_state: row.record_state === 'Archived' ? 'Active' : 'Archived',
					cancel_open_actions: row.record_state !== 'Archived'
				})
			});
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Archive failed.';
		}
	}

	async function logActivity(event: Event) {
		event.preventDefault();
		if (!row) return;
		error = '';
		try {
			const body: Record<string, unknown> = {
				company_id: row.company_id,
				contact_id: row.id,
				activity_type: 'Note',
				subject
			};
			if (nextDue && nextDesc) {
				body.follow_up = {
					action_type: 'Task',
					description: nextDesc,
					due_date: nextDue,
					contact_id: row.id
				};
			}
			await api('/v1/activities', { method: 'POST', body: JSON.stringify(body) });
			subject = '';
			nextDue = '';
			nextDesc = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not save activity.';
		}
	}
</script>

<svelte:head>
	<title>{row ? `${row.first_name} ${row.last_name}` : 'Contact'} — Stufe7</title>
</svelte:head>

<section class="card">
	<p><a href="/app/contacts">← Contacts</a></p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if row}
		<form onsubmit={save}>
			<label>First <input bind:value={row.first_name} required /></label>
			<label>Last <input bind:value={row.last_name} required /></label>
			<label>Job title <input bind:value={row.job_title} /></label>
			<label>Email <input bind:value={row.email} /></label>
			<label>Phone <input bind:value={row.telephone} /></label>
			<label>Notes <textarea bind:value={row.notes} rows="3"></textarea></label>
			<p><a href={`/app/companies/${row.company_id}`}>{row.company_name}</a></p>
			<div class="row">
				<button type="submit">Save</button>
				<button type="button" class="ghost" onclick={archive}>
					{row.record_state === 'Archived' ? 'Reactivate' : 'Archive'}
				</button>
			</div>
		</form>
		<h2>Quick activity</h2>
		<form onsubmit={logActivity}>
			<label>Subject <input bind:value={subject} required /></label>
			<label>Next action <input bind:value={nextDesc} /></label>
			<label>Due <input type="date" bind:value={nextDue} /></label>
			<button type="submit">Log</button>
		</form>
		<h2>Open actions</h2>
		<ul>
			{#each actions as item (item.id)}
				<li>{item.due_date} · {item.action_type}: {item.description}</li>
			{/each}
		</ul>
		<h2>History</h2>
		<ul>
			{#each activities as item (item.id)}
				<li>
					<a href={`/app/activities/${item.id}`}>{item.activity_date.slice(0, 10)} · {item.subject}</a>
				</li>
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
	.row {
		display: flex;
		gap: 0.6rem;
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
		padding: 0.5rem 0.7rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.55rem 0.9rem;
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
	}
</style>
