<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { api, withActiveEntity, type ActionItem, type Activity, type Contact } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Membership = { id: string; name: string; status: string; membership_status: string };

	const contactId = $derived(page.params.id);
	let row = $state<Contact | null>(null);
	let activities = $state<Activity[]>([]);
	let actions = $state<ActionItem[]>([]);
	let memberships = $state<Membership[]>([]);
	let error = $state('');
	let activityCampaign = $state('');
	let campaignStatus = $state('');
	let nextDue = $state('');
	let nextDesc = $state('');
	let closeId = $state('');
	let closeDue = $state('');
	let closeDesc = $state('');
	const campaignStatuses = [
		'Not Started',
		'Contacted',
		'Interested',
		'Qualified',
		'Demo / Meeting',
		'Proposal',
		'Won',
		'Lost',
		'Not Relevant'
	];

	function syncActivityCampaign() {
		if (memberships.length === 1) {
			activityCampaign = memberships[0].id;
			if (!campaignStatus) campaignStatus = memberships[0].membership_status;
			return;
		}
		if (!memberships.some((item) => item.id === activityCampaign)) {
			activityCampaign = '';
		}
	}

	async function load() {
		const contact = await api<Contact>(`/v1/contacts/${contactId}`);
		row = contact;
		[activities, actions, memberships] = await Promise.all([
			api<Activity[]>(`/v1/activities?contact_id=${contactId}`),
			api<ActionItem[]>(`/v1/actions?contact_id=${contactId}&horizon=open&scope=team`),
			api<Membership[]>(`/v1/companies/${contact.company_id}/campaigns`).catch(() => [] as Membership[])
		]);
		syncActivityCampaign();
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

	function openClose(id: string) {
		if (closeId === id) {
			closeId = '';
			closeDue = '';
			closeDesc = '';
			return;
		}
		closeId = id;
		closeDue = '';
		closeDesc = '';
	}

	async function closeAction(event: Event) {
		event.preventDefault();
		const item = actions.find((row) => row.id === closeId);
		if (!item || !row) return;
		if (Boolean(closeDesc.trim()) !== Boolean(closeDue)) {
			error = 'Enter both the next action and due date, or leave both blank.';
			return;
		}
		error = '';
		try {
			const body: Record<string, unknown> = {
				activity_type: 'Note',
				subject: item.description,
				outcome: 'Completed'
			};
			if (closeDesc.trim() && closeDue) {
				body.follow_up = {
					action_type: item.action_type || 'Task',
					description: closeDesc.trim(),
					due_date: closeDue,
					contact_id: row.id,
					campaign_id: item.campaign_id
				};
			}
			await api(`/v1/actions/${item.id}/complete`, {
				method: 'POST',
				body: JSON.stringify(body)
			});
			closeId = '';
			closeDue = '';
			closeDesc = '';
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not close action.';
		}
	}

	async function logActivity(event: Event) {
		event.preventDefault();
		if (!row) return;
		error = '';
		const campaignId = memberships.length === 1 ? memberships[0].id : activityCampaign;
		const campaign = memberships.find((item) => item.id === campaignId);
		if (!campaign || !campaignStatus) {
			error = 'Select the campaign and status for this activity.';
			return;
		}
		try {
			const body: Record<string, unknown> = {
				company_id: row.company_id,
				contact_id: row.id,
				activity_type: 'Note',
				subject: campaign.name,
				campaign_id: campaign.id,
				campaign_status: campaignStatus
			};
			if (nextDue && nextDesc) {
				body.follow_up = {
					action_type: 'Task',
					description: nextDesc,
					due_date: nextDue,
					contact_id: row.id,
					campaign_id: campaign.id
				};
			}
			await api('/v1/activities', { method: 'POST', body: JSON.stringify(body) });
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
		{#if !memberships.length}
			<p class="muted">Add this company to a campaign first, then log an activity.</p>
		{:else}
			<form onsubmit={logActivity}>
				<label>Campaign
					<select bind:value={activityCampaign} required>
						<option value="">Campaign</option>
						{#each memberships as item (item.id)}
							<option value={item.id}>{item.name}</option>
						{/each}
					</select>
				</label>
				<label>Status
					<select bind:value={campaignStatus} required>
						<option value="">Status</option>
						{#each campaignStatuses as status (status)}
							<option value={status}>{status}</option>
						{/each}
					</select>
				</label>
				<label>Next action <input bind:value={nextDesc} /></label>
				<label>Due <input type="date" bind:value={nextDue} /></label>
				<button type="submit">Log</button>
			</form>
		{/if}
		<h2>Open actions</h2>
		<ul>
			{#each actions as item (item.id)}
				<li>
					<div class="action-line">
						<span>{item.due_date} · {item.action_type}: {item.description}</span>
						<button type="button" class="ghost" onclick={() => openClose(item.id)}>
							{closeId === item.id ? 'Cancel' : 'Close'}
						</button>
					</div>
					{#if closeId === item.id}
						<form onsubmit={closeAction}>
							<label>Next action <input bind:value={closeDesc} /></label>
							<label>Due <input type="date" bind:value={closeDue} /></label>
							<button type="submit">Save</button>
						</form>
					{/if}
				</li>
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
	.row,
	.action-line {
		display: flex;
		gap: 0.6rem;
	}
	.action-line {
		justify-content: space-between;
		align-items: baseline;
	}
	input,
	select,
	textarea,
	button {
		font: inherit;
	}
	input,
	select,
	textarea {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.5rem 0.7rem;
	}
	.muted {
		color: #5b607a;
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
