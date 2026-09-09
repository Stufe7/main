<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api, type Company, type Member } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';

	const companyId = $derived($page.params.id);
	let row = $state<Company | null>(null);
	let members = $state<Member[]>([]);
	let error = $state('');
	let busy = $state(false);

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		try {
			[row, members] = await Promise.all([
				api<Company>(`/v1/companies/${companyId}`),
				api<Member[]>('/v1/members')
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
