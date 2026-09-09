<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { api, type SessionInfo } from '$lib/api/client';
	import { ensureActiveEntity } from '$lib/entity';

	let { children } = $props();
	let admin = $state(false);
	const path = $derived(page.url.pathname);

	onMount(async () => {
		try {
			const session = await api<SessionInfo>('/v1/session');
			const role = session.memberships.find(
				(row) => row.entity_id === ensureActiveEntity(session.memberships)
			)?.role;
			admin = role === 'Entity Admin';
		} catch {
			admin = false;
		}
	});
</script>

<nav class="tabs" aria-label="Settings">
	<a href="/app/settings/account" class:on={path.startsWith('/app/settings/account')}>Account</a>
	{#if admin}
		<a href="/app/settings/general" class:on={path.startsWith('/app/settings/general')}>General</a>
		<a href="/app/settings/users" class:on={path.startsWith('/app/settings/users')}>Users</a>
	{/if}
	<a href="/app/settings/digest" class:on={path.startsWith('/app/settings/digest')}>Digest</a>
	{#if admin}
		<a href="/app/settings/import" class:on={path.startsWith('/app/settings/import')}>Import</a>
		<a href="/app/settings/billing" class:on={path.startsWith('/app/settings/billing')}>Billing</a>
	{/if}
</nav>
{@render children()}

<style>
	.tabs {
		display: flex;
		flex-wrap: wrap;
		gap: 0.65rem 1rem;
		width: min(64rem, calc(100% - 2rem));
		margin: 1rem auto 0;
		padding-bottom: 0.35rem;
		border-bottom: 1px solid #e6e8f2;
	}
	.tabs a {
		color: #5b607a;
		font-weight: 650;
		text-decoration: none;
		padding: 0.2rem 0;
	}
	.tabs a.on {
		color: #20265e;
		box-shadow: 0 1px 0 #20265e;
	}
</style>
