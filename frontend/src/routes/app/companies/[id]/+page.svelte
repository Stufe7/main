<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api, type ActionItem, type Activity, type Company, type Contact, type Member } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	const companyId = $derived($page.params.id);
	let row = $state<Company | null>(null);
	let members = $state<Member[]>([]);
	let contacts = $state<Contact[]>([]);
	let activities = $state<Activity[]>([]);
	let actions = $state<ActionItem[]>([]);
	let error = $state('');
	let busy = $state(false);
	let subject = $state('');
	let nextDue = $state('');
	let nextDesc = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			[row, members, contacts, activities, actions] = await Promise.all([
				api<Company>(`/v1/companies/${companyId}`),
				api<Member[]>('/v1/members'),
				api<Contact[]>(`/v1/contacts?company_id=${companyId}`),
				api<Activity[]>(`/v1/activities?company_id=${companyId}`),
				api<ActionItem[]>(`/v1/actions?company_id=${companyId}&horizon=open&scope=team`)
			]);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load company.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		if (!row) return;
		busy = true;
		error = '';
		try {
			row = await api<Company>(`/v1/companies/${companyId}`, {
				method: 'PATCH',
				body: JSON.stringify({
					company_name: row.company_name,
					legal_name: row.legal_name,
					status: row.status,
					country: row.country,
					website: row.website,
					notes: row.notes,
					owner_user_id: row.owner_user_id,
					record_state: row.record_state
				})
			});
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		} finally {
			busy = false;
		}
	}

	async function logActivity(event: Event) {
		event.preventDefault();
		if (!row) return;
		busy = true;
		error = '';
		try {
			const body: Record<string, unknown> = {
				company_id: row.id,
				activity_type: 'Note',
				subject
			};
			if (nextDue && nextDesc) {
				body.follow_up = {
					action_type: 'Task',
					description: nextDesc,
					due_date: nextDue
				};
			}
			await api('/v1/activities', { method: 'POST', body: JSON.stringify(body) });
			subject = '';
			nextDue = '';
			nextDesc = '';
			activities = await api<Activity[]>(`/v1/activities?company_id=${companyId}`);
			actions = await api<ActionItem[]>(`/v1/actions?company_id=${companyId}&horizon=open&scope=team`);
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not save activity.';
		} finally {
			busy = false;
		}
	}

	async function archive() {
		if (!row) return;
		row.record_state = row.record_state === 'Archived' ? 'Active' : 'Archived';
		await save(new Event('submit'));
	}
</script>

<svelte:head>
	<title>{row?.company_name || 'Company'} — Stufe7</title>
</svelte:head>

<section class="card">
	<p><a href="/app/companies">← Companies</a></p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if row}
		<form onsubmit={save}>
			<h1>
				<input bind:value={row.company_name} required />
			</h1>
			<label>Status
				<select bind:value={row.status}>
					<option>Prospect</option>
					<option>Customer</option>
					<option>Former Customer</option>
					<option>Inactive</option>
				</select>
			</label>
			<label>Owner
				<select bind:value={row.owner_user_id}>
					<option value="">Unassigned</option>
					{#each members as member (member.user_id)}
						<option value={member.user_id}>{member.email}</option>
					{/each}
				</select>
			</label>
			<label>Country <input bind:value={row.country} /></label>
			<label>Website <input bind:value={row.website} /></label>
			<label>Notes <textarea bind:value={row.notes} rows="4"></textarea></label>
			<div class="actions">
				<button type="submit" disabled={busy}>Save</button>
				<button type="button" class="ghost" onclick={archive}>
					{row.record_state === 'Archived' ? 'Reactivate' : 'Archive'}
				</button>
			</div>
		</form>
		<p><a href={`/app/contacts/new?company=${row.id}`}>Add contact</a></p>
		<h2>Contacts</h2>
		<ul>
			{#each contacts as person (person.id)}
				<li>
					<a href={`/app/contacts/${person.id}`}>{person.first_name} {person.last_name}</a>
				</li>
			{/each}
		</ul>
		<h2>Quick activity</h2>
		<form onsubmit={logActivity}>
			<label>Subject <input bind:value={subject} required /></label>
			<label>Next action <input bind:value={nextDesc} /></label>
			<label>Due <input type="date" bind:value={nextDue} /></label>
			<button type="submit" disabled={busy}>Log</button>
		</form>
		<h2>Open actions</h2>
		<ul>
			{#each actions as item (item.id)}
				<li>{item.due_date} · {item.priority} · {item.description}</li>
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
		gap: 0.45rem;
	}
	h1 input {
		font: inherit;
		font-size: 1.4rem;
		font-weight: 700;
		border: 0;
		border-bottom: 1px solid #d5d8e6;
		width: 100%;
	}
	input,
	select,
	textarea {
		font: inherit;
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.7rem;
	}
	.actions {
		display: flex;
		gap: 0.75rem;
		margin-top: 0.5rem;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font: inherit;
		font-weight: 650;
		padding: 0.6rem 1rem;
		cursor: pointer;
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
