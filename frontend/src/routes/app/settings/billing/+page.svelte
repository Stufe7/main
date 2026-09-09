<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';

	let planCode = $state('');
	let planStatus = $state('');
	let error = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		const role = session.memberships.find(
			(row) => row.entity_id === ensureActiveEntity(session.memberships)
		)?.role;
		if (role !== 'Entity Admin') {
			error = 'Entity Admin access is required.';
			return;
		}
		try {
			const settings = await api<{ plan_code: string | null; plan_status: string | null }>(
				'/v1/settings/entity'
			);
			planCode = settings.plan_code || 'mvp';
			planStatus = settings.plan_status || 'Active';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load billing.';
		}
	});
</script>

<svelte:head>
	<title>Billing — Stufe7</title>
</svelte:head>

<section class="wrap">
	<p>Plan status for this entity. Invoicing is not in this release.</p>
	{#if error}
		<p class="error">{error}</p>
	{:else}
		<dl>
			<div><dt>Plan</dt><dd>{planCode}</dd></div>
			<div><dt>Status</dt><dd>{planStatus}</dd></div>
		</dl>
	{/if}
</section>

<style>
	.wrap {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
		display: grid;
		gap: 0.65rem;
	}
	dl {
		background: white;
		border-radius: 1rem;
		padding: 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
		display: grid;
		gap: 0.75rem;
	}
	div {
		display: grid;
		gap: 0.2rem;
	}
	dt {
		color: #5b607a;
		font-size: 0.9rem;
	}
	dd {
		margin: 0;
		font-weight: 650;
	}
	.error {
		background: #fde8e8;
		color: #8a1f1f;
		padding: 0.65rem;
		border-radius: 0.6rem;
	}
</style>
