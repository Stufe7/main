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
		type CompanyTaxonomy,
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
	let taxonomy = $state<CompanyTaxonomy>({ channels: [], segments: {} });
	let pickCampaign = $state('');
	let activityCampaign = $state('');
	let activityContact = $state('');
	let campaignStatus = $state('');
	let error = $state('');
	let info = $state('');
	let busy = $state(false);
	let loading = $state(true);
	let nextDue = $state('');
	let nextDesc = $state('');
	let closeId = $state('');
	let closeDue = $state('');
	let closeDesc = $state('');
	let noteText = $state('');
	let noteSource = $state('');
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

	function blank(value: string | null | undefined) {
		const text = (value ?? '').trim();
		return text || null;
	}

	function vacant(value: string | null | undefined) {
		return !(value ?? '').trim();
	}

	function websiteHref(value: string | null | undefined) {
		const text = (value ?? '').trim();
		if (!text) return '';
		const withProtocol = /^[a-z][a-z0-9+.-]*:/i.test(text) ? text : `https://${text}`;
		try {
			const url = new URL(withProtocol);
			if (url.protocol !== 'http:' && url.protocol !== 'https:') return '';
			return url.href;
		} catch {
			return '';
		}
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
			channel: company.channel ?? '',
			segment: company.segment ?? '',
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

	function personLabel(person: Contact) {
		return person.job_title
			? `${person.first_name} ${person.last_name} · ${person.job_title}`
			: `${person.first_name} ${person.last_name}`;
	}

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

	function syncActivityContact() {
		if (contacts.length === 1) {
			activityContact = contacts[0].id;
			return;
		}
		if (!contacts.some((person) => person.id === activityContact)) {
			activityContact = '';
		}
	}
	const siteHref = $derived(websiteHref(row?.website));
	const segmentOptions = $derived(
		row?.channel ? taxonomy.segments[row.channel] || [] : []
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
					membershipRows,
					taxonomyRows
				] = await Promise.all([
					api<Company>(`/v1/companies/${id}`),
					api<Member[]>('/v1/members'),
					api<Contact[]>(`/v1/contacts?company_id=${id}`),
					api<Activity[]>(`/v1/activities?company_id=${id}`),
					api<ActionItem[]>(`/v1/actions?company_id=${id}&horizon=open&scope=team`),
					api<Campaign[]>('/v1/campaigns').catch(() => [] as Campaign[]),
					api<Membership[]>(`/v1/companies/${id}/campaigns`).catch(() => [] as Membership[]),
					api<CompanyTaxonomy>('/v1/companies/taxonomy').catch(
						() => ({ channels: [], segments: {} }) as CompanyTaxonomy
					)
				]);
				row = hydrate(company);
				members = memberRows;
				contacts = contactRows;
				activities = activityRows;
				actions = actionRows;
				campaigns = campaignRows;
				memberships = membershipRows;
				taxonomy = taxonomyRows;
				syncActivityCampaign();
				syncActivityContact();
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
					channel: blank(row.channel),
					segment: blank(row.channel) ? blank(row.segment) : null,
					owner_user_id: row.owner_user_id,
					record_state: row.record_state
				})
			});
			row = hydrate(saved);
			taxonomy = await api<CompanyTaxonomy>('/v1/companies/taxonomy').catch(
				() => taxonomy
			);
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
			const campaignId = memberships.length === 1 ? memberships[0].id : activityCampaign;
			const campaign = memberships.find((item) => item.id === campaignId);
			if (!activityContact) {
				error = 'Select a contact for this activity.';
				busy = false;
				return;
			}
			if (!campaign || !campaignStatus) {
				error = 'Select the campaign and status for this activity.';
				busy = false;
				return;
			}
			const body: Record<string, unknown> = {
				company_id: row.id,
				contact_id: activityContact,
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
					contact_id: activityContact,
					campaign_id: campaign.id
				};
			}
			await api('/v1/activities', { method: 'POST', body: JSON.stringify(body) });
			nextDue = '';
			nextDesc = '';
			[activities, actions, memberships] = await Promise.all([
				api<Activity[]>(`/v1/activities?company_id=${companyId}`),
				api<ActionItem[]>(`/v1/actions?company_id=${companyId}&horizon=open&scope=team`),
				api<Membership[]>(`/v1/companies/${companyId}/campaigns`).catch(() => [] as Membership[])
			]);
			syncActivityCampaign();
			info = 'Activity logged.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not save activity.';
		} finally {
			busy = false;
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
		if (!item) return;
		if (Boolean(closeDesc.trim()) !== Boolean(closeDue)) {
			error = 'Enter both the next action and due date, or leave both blank.';
			return;
		}
		busy = true;
		error = '';
		info = '';
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
					contact_id: item.contact_id,
					campaign_id: item.campaign_id
				};
			}
			await api(`/v1/actions/${item.id}/complete`, {
				method: 'POST',
				body: JSON.stringify(body)
			});
			const hadFollowUp = Boolean(closeDesc.trim() && closeDue);
			closeId = '';
			closeDue = '';
			closeDesc = '';
			[activities, actions, memberships] = await Promise.all([
				api<Activity[]>(`/v1/activities?company_id=${companyId}`),
				api<ActionItem[]>(`/v1/actions?company_id=${companyId}&horizon=open&scope=team`),
				api<Membership[]>(`/v1/companies/${companyId}/campaigns`).catch(() => [] as Membership[])
			]);
			syncActivityCampaign();
			info = hadFollowUp ? 'Action closed and follow-up opened.' : 'Action closed.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not close action.';
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

	function downloadPdf() {
		window.print();
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
			syncActivityCampaign();
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
	<div class="toolbar no-print">
		<p class="back"><a href="/app/companies">← Companies</a></p>
		{#if row}
			<button type="button" class="ghost" onclick={downloadPdf}>Download PDF</button>
		{/if}
	</div>
	{#if loading}
		<p class="no-print">Loading…</p>
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
			<label>
				{#if vacant(row.parent_company)}<span>Parent company</span>{/if}
				<input bind:value={row.parent_company} aria-label="Parent company" />
			</label>
			<label>
				<select bind:value={row.status} aria-label="Status">
					<option>Prospect</option>
					<option>Customer</option>
					<option>Former Customer</option>
					<option>Inactive</option>
				</select>
			</label>
			<label>
				{#if vacant(row.channel)}<span>Channel</span>{/if}
				<input
					bind:value={row.channel}
					list="channel-options"
					aria-label="Channel"
					oninput={() => {
						if (row?.segment && segmentOptions.length && !segmentOptions.includes(row.segment)) {
							row.segment = '';
						}
					}}
				/>
			</label>
			<label>
				{#if vacant(row.segment)}<span>Segment</span>{/if}
				<input
					bind:value={row.segment}
					list="segment-options"
					aria-label="Segment"
					disabled={!row.channel}
				/>
			</label>
			<datalist id="channel-options">
				{#each taxonomy.channels as channel (channel)}
					<option value={channel}></option>
				{/each}
			</datalist>
			<datalist id="segment-options">
				{#each segmentOptions as segment (segment)}
					<option value={segment}></option>
				{/each}
			</datalist>
			<label>
				<select bind:value={row.owner_user_id} aria-label="Owner">
					<option value="">Unassigned</option>
					{#each members as member (member.user_id)}
						<option value={member.user_id}>{member.email}</option>
					{/each}
				</select>
			</label>
			<label>
				{#if vacant(row.country)}<span>Country</span>{/if}
				<input bind:value={row.country} maxlength="2" aria-label="Country" />
			</label>
			<label>
				{#if vacant(row.city)}<span>City</span>{/if}
				<input bind:value={row.city} aria-label="City" />
			</label>
			<label>
				{#if vacant(row.address)}<span>Address</span>{/if}
				<input bind:value={row.address} aria-label="Address" />
			</label>
			<div class="website">
				<label>
					{#if vacant(row.website)}<span>Website</span>{/if}
					<input bind:value={row.website} aria-label="Website" />
				</label>
				{#if siteHref}
					<a class="open no-print" href={siteHref} target="_blank" rel="noopener noreferrer">Open</a>
				{/if}
			</div>
			<label>
				{#if vacant(row.telephone)}<span>Telephone</span>{/if}
				<input bind:value={row.telephone} aria-label="Telephone" />
			</label>
			<label>
				{#if vacant(row.nature_of_business)}<span>Nature of business</span>{/if}
				<input bind:value={row.nature_of_business} aria-label="Nature of business" />
			</label>
			<div class="actions no-print">
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
							<button type="button" class="ghost small no-print" disabled={busy} onclick={() => removeNote(item.id)}>
								Remove
							</button>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No notes yet.</p>
			{/if}
			<form class="no-print" onsubmit={addNote}>
				<label>
					{#if vacant(noteText)}<span>Note</span>{/if}
					<input bind:value={noteText} required aria-label="Note" />
				</label>
				<label>
					{#if vacant(noteSource)}<span>Note source</span>{/if}
					<input bind:value={noteSource} aria-label="Note source" />
				</label>
				<button type="submit" disabled={busy}>Add note</button>
			</form>
		</section>
		<section class="card">
			<div class="head">
				<h2>Contacts</h2>
				<a class="no-print" href={`/app/contacts/new?company=${row.id}`}>Add contact</a>
			</div>
			{#if contacts.length}
				<ul>
					{#each contacts as person (person.id)}
						<li>
							<span>
								<a href={`/app/contacts/${person.id}`}>{person.first_name} {person.last_name}</a>
								{#if person.job_title}
									<span class="muted"> · {person.job_title}</span>
								{/if}
							</span>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No contacts yet.</p>
			{/if}
		</section>
		<section class="card">
			<h2>Activities</h2>
			<h3 class="no-print">Quick activity</h3>
			{#if !contacts.length}
				<p class="muted no-print">Add a contact first, then log an activity.</p>
			{:else if !memberships.length}
				<p class="muted no-print">Add this company to a campaign first, then log an activity.</p>
			{:else}
				<form class="no-print" onsubmit={logActivity}>
					<label>
						<select
							class:prompt={vacant(activityContact)}
							bind:value={activityContact}
							required
							aria-label="Contact"
						>
							<option value="">Contact</option>
							{#each contacts as person (person.id)}
								<option value={person.id}>{personLabel(person)}</option>
							{/each}
						</select>
					</label>
					<label>
						<select
							class:prompt={vacant(activityCampaign)}
							bind:value={activityCampaign}
							required
							aria-label="Campaign"
						>
							<option value="">Campaign</option>
							{#each memberships as item (item.id)}
								<option value={item.id}>{item.name}</option>
							{/each}
						</select>
					</label>
					<label>
						<select
							class:prompt={vacant(campaignStatus)}
							bind:value={campaignStatus}
							required
							aria-label="Status"
						>
							<option value="">Status</option>
							{#each campaignStatuses as status (status)}
								<option value={status}>{status}</option>
							{/each}
						</select>
					</label>
					<label>
						{#if vacant(nextDesc)}<span>Next action</span>{/if}
						<input bind:value={nextDesc} aria-label="Next action" />
					</label>
					<label>
						<input type="date" bind:value={nextDue} aria-label="Due" />
					</label>
					<button type="submit" disabled={busy}>Log</button>
				</form>
			{/if}
			<h3>Open actions</h3>
			{#if actions.length}
				<ul>
					{#each actions as item (item.id)}
						<li class="open-action">
							<div class="action-line">
								<span>{item.due_date} · {item.priority} · {item.description}</span>
								<button
									type="button"
									class="ghost small no-print"
									onclick={() => openClose(item.id)}
								>
									{closeId === item.id ? 'Cancel' : 'Close'}
								</button>
							</div>
							{#if closeId === item.id}
								<form class="close-form no-print" onsubmit={closeAction}>
									<label>
										{#if vacant(closeDesc)}<span>Next action</span>{/if}
										<input bind:value={closeDesc} aria-label="Next action" />
									</label>
									<label>
										<input type="date" bind:value={closeDue} aria-label="Due" />
									</label>
									<button type="submit" disabled={busy}>Save</button>
								</form>
							{/if}
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No open actions.</p>
			{/if}
			<h3>History</h3>
			{#if activities.length}
				<ul>
					{#each activities as item (item.id)}
						{@const person = contacts.find((row) => row.id === item.contact_id)}
						<li>
							<a href={`/app/activities/${item.id}`}>
								{item.activity_date.slice(0, 10)}{person
									? ` · ${personLabel(person)}`
									: ''}{item.subject ? ` · ${item.subject}` : ''}{item.outcome
									? ` · ${item.outcome}`
									: ''}
							</a>
						</li>
					{/each}
				</ul>
			{:else}
				<p class="muted">No activity yet.</p>
			{/if}
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
				<form class="no-print" onsubmit={addToCampaign}>
					<label>
						<select
							class:prompt={vacant(pickCampaign)}
							bind:value={pickCampaign}
							required
							aria-label="Add to campaign"
						>
							<option value="">Add to campaign</option>
							{#each addableCampaigns as item (item.id)}
								<option value={item.id}>{item.name}</option>
							{/each}
						</select>
					</label>
					<button type="submit" disabled={busy}>Add to campaign</button>
				</form>
			{:else if campaigns.some((item) => item.status === 'Planned' || item.status === 'Active')}
				<p class="muted no-print">This company is already on every Planned or Active campaign.</p>
			{:else}
				<p class="muted no-print">Create a Planned or Active campaign first, then add this company to it.</p>
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
	.toolbar {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}
	.card {
		background: white;
		border-radius: 1rem;
		padding: 1.25rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
		display: grid;
		gap: 0.6rem;
	}
	form {
		display: grid;
		gap: 0.5rem;
	}
	label {
		position: relative;
		display: block;
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.75rem;
		font-size: 1.05rem;
		font-weight: 650;
		color: #5b607a;
	}
	label span {
		position: absolute;
		left: 0.75rem;
		top: 50%;
		transform: translateY(-50%);
		pointer-events: none;
		font-weight: 400;
		color: #8b90a5;
	}
	label:focus-within {
		border-color: #20265e;
	}
	h1,
	h2,
	h3,
	p,
	ul {
		margin: 0;
	}
	h2 {
		font-size: 1.25rem;
		color: #20265e;
	}
	h3 {
		font-size: 1.05rem;
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
		font-size: 1.05rem;
		color: #20265e;
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.55rem 0.7rem;
	}
	label :is(input, select, textarea) {
		border: 0;
		border-radius: 0;
		padding: 0;
		background: transparent;
		width: 100%;
		min-width: 0;
		font-size: 1.05rem;
		font-weight: 500;
	}
	.website {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding-right: 0.55rem;
	}
	.website:focus-within {
		border-color: #20265e;
	}
	.website label {
		flex: 1;
		min-width: 0;
		border: 0;
	}
	.open {
		flex-shrink: 0;
		font-size: 0.9rem;
		font-weight: 650;
		text-decoration: none;
		white-space: nowrap;
	}
	label select.prompt {
		font-weight: 400;
		color: #8b90a5;
	}
	label :is(input, select, textarea):focus {
		outline: none;
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
	.card li.open-action {
		display: grid;
		gap: 0.4rem;
	}
	.action-line {
		display: flex;
		justify-content: space-between;
		gap: 0.75rem;
		align-items: baseline;
	}
	.close-form {
		display: grid;
		gap: 0.4rem;
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
	@media print {
		.wrap {
			width: 100%;
			margin: 0;
			gap: 0.35rem;
			font-size: 11pt;
			line-height: 1.25;
		}
		.wrap :is(h1, h2, h3, p, li, a, label, input, select, textarea, span, button) {
			font-size: 11pt;
			line-height: 1.25;
		}
		.card,
		form {
			gap: 0.25rem;
		}
		.card {
			padding: 0.35rem 0.45rem;
			box-shadow: none;
			border: 1px solid #d5d8e6;
		}
		label {
			padding: 0.12rem 0.35rem;
		}
		h1 input {
			border-bottom: 0;
		}
		li {
			padding: 0.08rem 0;
			break-inside: avoid;
		}
		label:has(span),
		.website:has(span) {
			display: none;
		}
		input,
		select,
		textarea {
			border-color: transparent;
			appearance: none;
			background: transparent;
			padding: 0;
		}
		.error,
		.info {
			display: none;
		}
	}
</style>
