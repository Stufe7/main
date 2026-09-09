<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { api, type Company, type Member, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

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
	type Row = {
		id: string;
		company_id: string;
		company_name: string;
		country: string | null;
		status: string;
		owner_user_id: string | null;
		effective_owner_user_id: string | null;
		next_action_due_date: string | null;
	};

	const campaignId = $derived(page.params.id);
	let campaign = $state<Campaign | null>(null);
	let members = $state<Member[]>([]);
	let companies = $state<Row[]>([]);
	let catalog = $state<Company[]>([]);
	let addCompanyId = $state('');
	let error = $state('');
	let info = $state('');
	let due = $state('');
	let nextDesc = $state('');
	let actionCompany = $state('');
	let cancelOpen = $state(false);
	let busy = $state(false);
	let filter = $state('');

	const nameOf = (id: string | null) => {
		if (!id) return 'Unassigned';
		const member = members.find((row) => row.user_id === id);
		return member ? member.email : id.slice(0, 8);
	};

	const available = $derived(
		catalog.filter((row) => {
			if (companies.some((item) => item.company_id === row.id)) return false;
			const needle = filter.trim().toLowerCase();
			if (!needle) return true;
			return row.company_name.toLowerCase().includes(needle);
		})
	);

	async function load() {
		const id = campaignId;
		if (!id) return;
		campaign = await api<Campaign>(`/v1/campaigns/${id}`);
		if (campaign.start_date) campaign.start_date = campaign.start_date.slice(0, 10);
		if (campaign.end_date) campaign.end_date = campaign.end_date.slice(0, 10);
		members = await api<Member[]>('/v1/members');
		companies = await api<Row[]>(`/v1/campaigns/${id}/companies`);
		catalog = await api<Company[]>('/v1/companies');
	}

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		ensureActiveEntity(session.memberships);
		try {
			await load();
			if (page.url.searchParams.get('saved') === '1') {
				info = 'Campaign saved.';
			}
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load campaign.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		if (!campaign || busy) return;
		error = '';
		info = '';
		busy = true;
		try {
			await api(`/v1/campaigns/${campaign.id}`, {
				method: 'PATCH',
				body: JSON.stringify({
					name: campaign.name,
					description: campaign.description,
					owner_user_id: campaign.owner_user_id,
					start_date: campaign.start_date,
					end_date: campaign.end_date,
					status: campaign.status,
					record_state: campaign.record_state,
					cancel_open_actions: cancelOpen
				})
			});
			await load();
			info = 'Campaign saved.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		} finally {
			busy = false;
		}
	}

	async function addCompany(event: Event) {
		event.preventDefault();
		if (!addCompanyId) return;
		error = '';
		info = '';
		try {
			await api(`/v1/campaigns/${campaignId}/companies`, {
				method: 'POST',
				body: JSON.stringify({ company_ids: [addCompanyId] })
			});
			const added = catalog.find((row) => row.id === addCompanyId);
			addCompanyId = '';
			filter = '';
			await load();
			info = added ? `${added.company_name} added to this campaign.` : 'Company added to this campaign.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not add company.';
		}
	}

	async function removeCompany(companyId: string) {
		error = '';
		info = '';
		try {
			await api(`/v1/campaigns/${campaignId}/companies/${companyId}`, {
				method: 'PATCH',
				body: JSON.stringify({ record_state: 'Archived' })
			});
			await load();
			info = 'Company removed from this campaign.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not remove company.';
		}
	}

	async function setStatus(companyId: string, status: string) {
		error = '';
		try {
			await api(`/v1/campaigns/${campaignId}/companies/${companyId}`, {
				method: 'PATCH',
				body: JSON.stringify({ status })
			});
			await load();
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not update status.';
		}
	}

	async function addAction(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		try {
			await api('/v1/actions', {
				method: 'POST',
				body: JSON.stringify({
					company_id: actionCompany,
					campaign_id: campaignId,
					action_type: 'Task',
					description: nextDesc,
					due_date: due,
					priority: 'Normal'
				})
			});
			nextDesc = '';
			due = '';
			await load();
			info = 'Action added.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Action failed.';
		}
	}
</script>

<svelte:head>
	<title>{campaign?.name || 'Campaign'} — Stufe7</title>
</svelte:head>

<section class="wrap">
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	{#if campaign}
		<form class="card" onsubmit={save}>
			<label>Name <input bind:value={campaign.name} required /></label>
			<label>Description <textarea bind:value={campaign.description}></textarea></label>
			<label>Start <input type="date" bind:value={campaign.start_date} required /></label>
			<label>End <input type="date" bind:value={campaign.end_date} required /></label>
			<label>Status
				<select bind:value={campaign.status}>
					<option>Planned</option>
					<option>Active</option>
					<option>Completed</option>
					<option>Cancelled</option>
				</select>
			</label>
			<label>
				<input type="checkbox" bind:checked={cancelOpen} />
				Cancel open campaign actions if the end date moves earlier
			</label>
			<button type="submit" disabled={busy}>{busy ? 'Saving…' : 'Save campaign'}</button>
		</form>
		<section class="card">
			<h2>Add companies</h2>
			{#if !catalog.length}
				<p class="muted">No companies yet. Create a company first, then add it here.</p>
			{:else if !available.length && !filter.trim()}
				<p class="muted">Every company is already on this campaign.</p>
			{:else}
				<form onsubmit={addCompany}>
					<label>Filter
						<input bind:value={filter} placeholder="Type to narrow the list" />
					</label>
					<label>Company
						<select bind:value={addCompanyId} required>
							<option value="">Select…</option>
							{#each available as row (row.id)}
								<option value={row.id}>{row.company_name}</option>
							{/each}
						</select>
					</label>
					<button type="submit">Add to campaign</button>
				</form>
			{/if}
		</section>
		<section class="card">
			<h2>Campaign action</h2>
			<form onsubmit={addAction}>
				<label>Company
					<select bind:value={actionCompany} required>
						<option value="">Select…</option>
						{#each companies as row (row.company_id)}
							<option value={row.company_id}>{row.company_name}</option>
						{/each}
					</select>
				</label>
				<label>Next action <input bind:value={nextDesc} required /></label>
				<label>Due <input type="date" bind:value={due} required /></label>
				<button type="submit">Add action</button>
			</form>
		</section>
		<ul class="list">
			{#each companies as row (row.id)}
				<li>
					<a href={`/app/companies/${row.company_id}`}>{row.company_name}</a>
					<span>{row.country || '—'} · {nameOf(row.effective_owner_user_id)}</span>
					<select value={row.status} onchange={(event) => setStatus(row.company_id, event.currentTarget.value)}>
						<option>Not Started</option>
						<option>Contacted</option>
						<option>Interested</option>
						<option>Qualified</option>
						<option>Demo / Meeting</option>
						<option>Proposal</option>
						<option>Won</option>
						<option>Lost</option>
						<option>Not Relevant</option>
					</select>
					<button type="button" class="ghost" onclick={() => removeCompany(row.company_id)}>Remove</button>
				</li>
			{/each}
		</ul>
	{/if}
</section>

<style>
	.wrap {
		width: min(56rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 1rem;
	}
	.card,
	form,
	label {
		display: grid;
		gap: 0.4rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1rem 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	.list {
		list-style: none;
		padding: 0;
		margin: 0;
		background: white;
		border-radius: 1rem;
		overflow: hidden;
	}
	li {
		display: flex;
		flex-wrap: wrap;
		gap: 0.6rem;
		align-items: center;
		padding: 0.75rem 1rem;
		border-bottom: 1px solid #eef0f6;
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
	button:disabled {
		opacity: 0.7;
		cursor: wait;
	}
	.ghost {
		background: white;
		color: #20265e;
		border: 1px solid #20265e;
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
		margin: 0;
	}
	a {
		color: #20265e;
		font-weight: 650;
	}
	span {
		color: #5b607a;
	}
</style>
