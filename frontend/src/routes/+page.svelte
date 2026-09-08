<script lang="ts">
	import AuthModal from '$lib/auth/AuthModal.svelte';

	let authOpen = $state(false);
	let authTab = $state<'login' | 'signup'>('signup');

	function openAuth(tab: 'login' | 'signup') {
		authTab = tab;
		authOpen = true;
	}

	const features = [
		{
			title: 'Companies & Contacts',
			line: 'Your customer directory in one place.'
		},
		{
			title: 'Activities',
			line: 'A fast history of every call, email, meeting and message.'
		},
		{
			title: 'Next Actions',
			line: 'An action-oriented work queue, sorted by what’s due.'
		},
		{
			title: 'Campaigns',
			line: 'Group companies into focused sales initiatives.'
		},
		{
			title: 'Action Digest',
			line: 'A daily, weekly or monthly email of what’s overdue and due.'
		},
		{
			title: 'Verified Company Access',
			line: 'Company email and website are checked during signup; unverified registrations are reviewed before access is granted.'
		}
	];
</script>

<svelte:head>
	<title>Stufe7 — Lightweight. Focused. For What’s Next.</title>
	<meta
		name="description"
		content="Keep track of your companies, contacts, conversations and next actions — all in one place."
	/>
</svelte:head>

<div class="page">
	<header class="nav">
		<img src="/stufe7-logo.svg" alt="Stufe7" class="wordmark" />
		<p class="tagline">Lightweight. Focused. For What’s Next.</p>
		<div class="nav-actions">
			<button type="button" class="ghost" onclick={() => openAuth('login')}>Log in</button>
			<button type="button" class="solid" onclick={() => openAuth('signup')}>Sign up</button>
		</div>
	</header>

	<section class="hero">
		<img src="/stufe7-mark.svg" alt="" class="mark" />
		<h1>Build stronger customer relationships</h1>
		<p>
			Keep track of your companies, contacts, conversations and next actions — all in one place.
		</p>
		<div class="hero-actions">
			<button type="button" class="solid" onclick={() => openAuth('signup')}>Get started free</button>
			<button type="button" class="ghost" onclick={() => openAuth('login')}>Log in</button>
		</div>
	</section>

	<section class="features">
		{#each features as feature (feature.title)}
			<article>
				<h2>{feature.title}</h2>
				<p>{feature.line}</p>
			</article>
		{/each}
	</section>

	<section class="devices">
		<h2>A simple, intuitive CRM that works on any device.</h2>
		<ul>
			<li>Desktop</li>
			<li>Tablet</li>
			<li>Mobile</li>
		</ul>
	</section>

	<footer>
		<div class="footer-actions">
			<button type="button" class="solid" onclick={() => openAuth('signup')}>Sign up</button>
			<button type="button" class="ghost" onclick={() => openAuth('login')}>Log in</button>
		</div>
		<p>
			<a href="mailto:support@stufe7.com">support@stufe7.com</a>
			·
			<a href="mailto:privacy@stufe7.com">privacy@stufe7.com</a>
		</p>
	</footer>
</div>

<AuthModal bind:open={authOpen} bind:tab={authTab} />

<style>
	.page {
		min-height: 100vh;
		background: #f6f7fb;
		color: #20265e;
	}
	.nav,
	.hero,
	.features,
	.devices,
	footer {
		width: min(72rem, calc(100% - 2rem));
		margin-inline: auto;
	}
	.nav {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.75rem 1.25rem;
		padding: 1.25rem 0;
	}
	.wordmark {
		height: 1.75rem;
		width: auto;
	}
	.tagline {
		margin: 0;
		flex: 1;
		color: #5b607a;
		font-size: 0.95rem;
	}
	.nav-actions,
	.hero-actions,
	.footer-actions {
		display: flex;
		gap: 0.6rem;
	}
	.hero {
		padding: 3rem 0 4rem;
		max-width: 46rem;
	}
	.mark {
		width: 3rem;
		height: 3rem;
		margin-bottom: 1.25rem;
	}
	h1 {
		margin: 0 0 1rem;
		font-size: clamp(2rem, 5vw, 3.4rem);
		line-height: 1.1;
	}
	.hero p {
		font-size: 1.15rem;
		color: #3c4160;
		max-width: 36rem;
	}
	.features {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(16rem, 1fr));
		gap: 1rem;
		padding-bottom: 3rem;
	}
	article,
	.devices {
		background: white;
		border-radius: 1rem;
		padding: 1.25rem;
		box-shadow: 0 10px 30px rgb(32 38 94 / 0.06);
	}
	article h2,
	.devices h2 {
		margin: 0 0 0.4rem;
		font-size: 1.05rem;
	}
	article p,
	.devices ul {
		margin: 0;
		color: #5b607a;
	}
	.devices {
		margin-bottom: 3rem;
	}
	.devices ul {
		display: flex;
		gap: 1rem;
		padding: 1rem 0 0;
		list-style: none;
		font-weight: 650;
		color: #20265e;
	}
	footer {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 1rem;
		padding: 1.5rem 0 2.5rem;
		color: #5b607a;
	}
	footer a {
		color: #20265e;
	}
	button {
		font: inherit;
		cursor: pointer;
	}
	.solid,
	.ghost {
		border-radius: 999px;
		padding: 0.6rem 1.05rem;
		font-weight: 650;
	}
	.solid {
		border: 0;
		background: #20265e;
		color: white;
	}
	.ghost {
		border: 1px solid #20265e;
		background: white;
		color: #20265e;
	}
	@media (max-width: 640px) {
		.nav-actions {
			margin-left: auto;
		}
	}
</style>
