<script lang="ts">
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { api, type SessionInfo } from '$lib/api/client';
	import { requireSession } from '$lib/auth/session.svelte';
	import { ensureActiveEntity } from '$lib/entity';
	import { listTimeZones } from '$lib/signup/timezones';

	const frequencies = ['Off', 'Daily', 'Weekly', 'Monthly'] as const;

	let frequency = $state('Daily');
	let timezone = $state('');
	let originalTimezone = $state('');
	let zones = $state<string[]>([]);
	let confirmShift = $state(false);
	let error = $state('');
	let info = $state('');

	onMount(async () => {
		if (!(await requireSession())) {
			await goto('/');
			return;
		}
		const session = await api<SessionInfo>('/v1/session');
		if (!ensureActiveEntity(session.memberships)) {
			error = 'No entity membership.';
			return;
		}
		zones = listTimeZones();
		try {
			const settings = await api<{ digest_frequency: string; timezone: string }>(
				'/v1/settings/entity'
			);
			frequency = settings.digest_frequency;
			timezone = settings.timezone;
			originalTimezone = settings.timezone;
		} catch (err) {
			error = err instanceof Error ? err.message : 'Could not load digest settings.';
		}
	});

	async function save(event: Event) {
		event.preventDefault();
		error = '';
		info = '';
		if (timezone !== originalTimezone && !confirmShift) {
			error =
				'Changing your timezone shifts Today, Overdue, This Week, displayed due times, and digest timing immediately. Confirm to continue.';
			return;
		}
		try {
			await api('/v1/settings/digest', {
				method: 'PATCH',
				body: JSON.stringify({ frequency, timezone })
			});
			originalTimezone = timezone;
			confirmShift = false;
			info = 'Digest settings saved.';
		} catch (err) {
			error = err instanceof Error ? err.message : 'Save failed.';
		}
	}
</script>

<svelte:head>
	<title>Action Digest — Stufe7</title>
</svelte:head>

<section class="wrap">
	<h1>Action Digest</h1>
	<p>
		Your timezone defines Today, Overdue, This Week, and when the digest is sent. Daily covers today,
		Weekly the current Monday–Sunday week, Monthly the calendar month. Off sends nothing.
	</p>
	{#if error}
		<p class="error">{error}</p>
	{/if}
	{#if info}
		<p class="info">{info}</p>
	{/if}
	<form onsubmit={save}>
		<label>Your timezone
			<select bind:value={timezone}>
				{#each zones as zone (zone)}
					<option value={zone}>{zone}</option>
				{/each}
			</select>
		</label>
		{#if timezone !== originalTimezone}
			<label>
				<input type="checkbox" bind:checked={confirmShift} />
				I understand calendar boundaries and digest timing will shift immediately.
			</label>
		{/if}
		{#each frequencies as option (option)}
			<label>
				<input type="radio" name="frequency" value={option} bind:group={frequency} />
				{option}
			</label>
		{/each}
		<button type="submit">Save</button>
	</form>
</section>

<style>
	.wrap,
	form,
	label {
		display: grid;
		gap: 0.65rem;
	}
	.wrap {
		width: min(40rem, calc(100% - 2rem));
		margin: 1.5rem auto 3rem;
	}
	form {
		background: white;
		border-radius: 1rem;
		padding: 1.1rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	label {
		display: flex;
		gap: 0.5rem;
		align-items: center;
	}
	select,
	button {
		font: inherit;
	}
	select {
		border: 1px solid #d5d8e6;
		border-radius: 0.5rem;
		padding: 0.4rem 0.55rem;
		width: 100%;
	}
	button {
		border: 0;
		border-radius: 999px;
		background: #20265e;
		color: white;
		font-weight: 650;
		padding: 0.45rem 0.9rem;
		width: fit-content;
		cursor: pointer;
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
</style>
