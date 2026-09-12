<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import {
		api,
		withActiveEntity,
		type ActionItem,
		type Activity,
		type Company,
		type CompanyNote,
		type Contact,
		type Member
	} from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	type Campaign = { id: string; name: string; status: string };
	type Membership = { id: string; name: string; status: string; membership_status: string };

	const companyId = $derived(page.params.id);
	let row = $state<Company | null>(null);
	let members = $state<Member[]>([]);
	let contacts = $state<Contact[]>([]);
	let activities = $state<Activity[]>([]);
	let actions = $state<ActionItem[]>([]);
	let campaigns = $state<Campaign[]>([]);
	let memberships = $state<Membership[]>([]);
	let pickCampaign = $state('');
	let error = $state('');
	let info = $state('');
	let busy = $state(false);
	let loading = $state(true);
	let subject = $state('');
	let nextDue = $state('');
	let nextDesc = $state('');
	let noteText = $state('');
	let noteSource = $state('');

	function blank(value: string | null | undefined) {
		const text = (value ?? '').trim();
		return text || null;
	}

	function hydrate(company: Company): Company {
		return {
			...company,
			parent_company: company.parent_company ?? '',
			country: company.country ?? '',
			city: company.city ?? '',
			address: company.address ?? '',
			website: company.website ?? '',
			telephone: company.telephone ?? '',
			nature_of_business: company.nature_of_business ?? '',
			notes: company.notes ?? []
		};
	}

	const addableCampaigns = $derived(
		campaigns.filter(
			(item) =>
				(item.status === 'Planned' || item.status === 'Active') &&
				!memberships.some((row) => row.id === item.id)
		)
	);

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			const id = page.params.id;
			if (!id) {
				error = 'Missing company.';
				return;
			}
			await withActiveEntity(async () => {
				const [
					company,
					memberRows,
					contactRows,
					activityRows,
					actionRows,
					campaignRows,
					membershipRows
				] = await Promise.all([
					api<Company>(`/v1/companies/${id}`),
					api<Member[]>('/v1/members'),
					api<Contact[]>(`/v1/contacts?company_id=${id}`),
					api<Activity[]>(`/v1/activities?company_id=${id}`),
					api<ActionItem[]>(`/v1/actions?company_id=${id}&horizon=open&scope=team`),
					api<Campaign[]>('/v1/campaigns').catch(() => [] as Campaign[]),
					api<Membership[]>(`/v1/companies/${id}/campaigns`).catch(() => [] as Membership[])
				]);
				row = hydrate(company);
				members = memberRows;
				contacts = contactRows;
				activities = activityRows;
				actions = actionRows;
				campaigns = campaignRows;
				memberships = membershipRows;
			});
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load company.';
		} finally {
			loading = false;
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		if (!row) return;
		busy = true;
		error = '';
		info = '';
		try {
			const saved = await api<Company>(`/v1/companies/${companyId}`, {
				method: 'PATCH',
				body: JSON.stringify({
					company_name: row.company_name,
					parent_company: blank(row.parent_company),
					status: row.status,
					country: blank(row.country),
					city: blank(row.city),
					address: blank(row.address),
					website: blank(row.website),
					telephone: blank(row.telephone),
					nature_of_business: blank(row.nature_of_business),
					owner_user_id: row.owner_user_id,
					record_state: row.record_state
				})
			});
			row = hydrate(saved);
			info = 'Company saved.';
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
		info = '';
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
			info = 'Activity logged.';
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

	async function addNote(event: Event) {
		event.preventDefault();
		if (!row || !noteText.trim()) return;
		busy = true;
		error = '';
		info = '';
		try {
			const created = await api<CompanyNote>(`/v1/companies/${companyId}/notes`, {
				method: 'POST',
				body: JSON.stringify({
					note: noteText.trim(),
					source: noteSource.trim() || null
				})
			});
			row = { ...row, notes: [...row.notes, created] };
			noteText = '';
			noteSource = '';
			info = 'Note added.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not add note.';
		} finally {
			busy = false;
		}
	}

	async function removeNote(noteId: string) {
		if (!row) return;
		busy = true;
		error = '';
		info = '';
		try {
			await api(`/v1/companies/${companyId}/notes/${noteId}`, { method: 'DELETE' });
			row = { ...row, notes: row.notes.filter((item) => item.id !== noteId) };
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not remove note.';
		} finally {
			busy = false;
		}
	}

	async function addToCampaign(event: Event) {
		event.preventDefault();
		if (!pickCampaign || !companyId) return;
		busy = true;
		error = '';
		info = '';
		try {
			await api(`/v1/campaigns/${pickCampaign}/companies`, {
				method: 'POST',
				body: JSON.stringify({ company_ids: [companyId] })
			});
			const chosen = campaigns.find((item) => item.id === pickCampaign);
			pickCampaign = '';
			memberships = await api<Membership[]>(`/v1/companies/${companyId}/campaigns`);
			info = chosen ? `Added to ${chosen.name}.` : 'Added to campaign.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not add to campaign.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>{row?.company_name || 'Company'} — Stufe7</title>
</svelte:head>

<section class="wrap">
	<p class="back"><a href="/app/companies">← Companies</a></p>
	{#if loading}
		<p>Loading…</p>
	{/if}
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	{#if row}
		<form class="card" onsubmit={save}>
			<h1>
				<input bind:value={row.company_name} required />
			</h1>
			<label>Parent company
				<input bind:value={row.parent_company} />
			</label>
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
			<label>Country <input bind:value={row.country} maxlength="2" /></label>
			<label>City <input bind:value={row.city} /></label>
			<label>Address <input bind:value={row.address} /></label>
			<label>Website <input bind:value={row.website} /></label>
			<label>Telephone <input bind:value={row.telephone} /></label>
			<label>Nature of business <input bind:value={row.nature_of_business} /></label>
			<div class="actions">
				<button type="submit" disabled={busy}>Save</button>
				<button type="button" class="ghost" onclick={archive}>
					{row.record_state === 'Archived' ? 'Reactivate' : 'Archive'}
				</button>
			</div>
		</form>
		<section class="card">
			<h2>Notes</h2>
			{#if row.notes.length}
				<ul>
					{#each row.notes as item (item.id)}
						<li>
							<span>
								{item.note}
								{#if item.source}
									<span class="muted"> · {item.source}</span>
								{/if}
							</span>
							<button type="button" class="ghost small" disabled={busy} onclick={() => removeNote(item.id)}>
								Remove
							</button>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No notes yet.</p>
			{/if}
			<form onsubmit={addNote}>
				<label>Note <input bind:value={noteText} required placeholder="ZGW operator" /></label>
				<label>Note source <input bind:value={noteSource} placeholder="Website" /></label>
				<button type="submit" disabled={busy}>Add note</button>
			</form>
		</section>
		<section class="card">
			<h2>Campaigns</h2>
			{#if memberships.length}
				<ul>
					{#each memberships as item (item.id)}
						<li>
							<a href={`/app/campaigns/${item.id}`}>{item.name}</a>
							<span class="muted"> · {item.status} · {item.membership_status}</span>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">Not on a campaign yet.</p>
			{/if}
			{#if addableCampaigns.length}
				<form onsubmit={addToCampaign}>
					<label>Add to campaign
						<select bind:value={pickCampaign} required>
							<option value="">Select…</option>
							{#each addableCampaigns as item (item.id)}
								<option value={item.id}>{item.name}</option>
							{/each}
						</select>
					</label>
					<button type="submit" disabled={busy}>Add to campaign</button>
				</form>
			{:else if campaigns.some((item) => item.status === 'Planned' || item.status === 'Active')}
				<p class="muted">This company is already on every Planned or Active campaign.</p>
			{:else}
				<p class="muted">Create a Planned or Active campaign first, then add this company to it.</p>
			{/if}
		</section>
		<section class="card">
			<div class="head">
				<h2>Contacts and activity</h2>
				<a href={`/app/contacts/new?company=${row.id}`}>Add contact</a>
			</div>
			{#if contacts.length}
				<ul>
					{#each contacts as person (person.id)}
						<li>
							<a href={`/app/contacts/${person.id}`}>{person.first_name} {person.last_name}</a>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No contacts yet.</p>
			{/if}
			<h2>Quick activity</h2>
			<form onsubmit={logActivity}>
				<label>Subject <input bind:value={subject} required /></label>
				<label>Next action <input bind:value={nextDesc} /></label>
				<label>Due <input type="date" bind:value={nextDue} /></label>
				<button type="submit" disabled={busy}>Log</button>
			</form>
			<h2>Open actions</h2>
			{#if actions.length}
				<ul>
					{#each actions as item (item.id)}
						<li>{item.due_date} · {item.priority} · {item.description}</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No open actions.</p>
			{/if}
			<h2>History</h2>
			{#if activities.length}
				<ul>
					{#each activities as item (item.id)}
						<li>
							<a href={`/app/activities/${item.id}`}>{item.activity_date.slice(0, 10)} · {item.subject}</a>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No activity yet.</p>
			{/if}
		</section>
	{/if}
</section>

<style>
	.wrap {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 1rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.5rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
		display: grid;
		gap: 0.75rem;
	}
	form,
	label {
		display: grid;
		gap: 0.45rem;
	}
	h1,
	h2,
	p,
	ul {
		margin: 0;
	}
	h2 {
		font-size: 1.15rem;
		color: #20265e;
	}
	.head {
		display: flex;
		align-items: baseline;
		justify-content: space-between;
		gap: 1rem;
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
		width: fit-content;
	}
	.ghost {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
	}
	.small {
		padding: 0.25rem 0.7rem;
		font-size: 0.85rem;
	}
	.card li {
		display: flex;
		justify-content: space-between;
		gap: 0.75rem;
		align-items: baseline;
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
	.muted {
		color: #5b607a;
	}
	.back {
		margin: 0;
	}
	ul {
		list-style: none;
		padding: 0;
	}
	li {
		padding: 0.35rem 0;
	}
	a {
		color: #20265e;
		font-weight: 650;
	}
</style>
