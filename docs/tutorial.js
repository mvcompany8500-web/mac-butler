// 사사리사 첫 칸의 움직이는 사용 예시 — 맥 화면 위에서 실제 앱 카드가 「듣는 중 → 하는 중 → 결과」로 바뀌고, 뒤의 화면이 그 일로 넘어갑니다.
(() => {
  const root = document.querySelector('.tut'); if (!root) return;
  const ko = (document.documentElement.lang || 'ko').startsWith('ko');
  // the same words and states the app shows (DemoFrames.swift / Strings.swift)
  const scenes = ko ? [
    { k: 'yt', say: '사사리사, 유튜브 로파이 틀어', work: '◌ 유튜브 찾는 중', state: '▶ 유튜브 재생', body: '비 오는 밤, 공부할 때 듣는 로파이 라디오 ☔' },
    { k: 'shop', say: '사사리사, 쿠팡에서 맥미니 찾아 줘', work: '◌ 쿠팡 여는 중', state: '✓ 쿠팡 검색', body: '「맥미니」 검색 결과를 열었어요' },
    { k: 'claude', say: '사사리사, 클로드한테 로그인 버그 고치라고 해', work: '◌ 클로드 여는 중', state: '✓ 클로드에 보냄', body: '로그인 버그 고치라고 해' },
    { k: 'timer', say: '사사리사, 라면 3분', state: '✓ 타이머', body: '라면 · 3분 뒤에 알려 드릴게요' },
  ] : [
    { k: 'yt', say: 'Sasarisa, play some lofi on YouTube', work: '◌ Finding it on YouTube', state: '▶ Playing on YouTube', body: 'Rainy-night lofi radio for studying ☔' },
    { k: 'shop', say: 'Sasarisa, find me a Mac mini', work: '◌ Opening a shopping search', state: '✓ Shopping search', body: 'Opened the results for “Mac mini”' },
    { k: 'claude', say: 'Sasarisa, tell Claude to fix the login bug', work: '◌ Opening Claude', state: '✓ Sent to Claude', body: 'Fix the login bug' },
    { k: 'timer', say: 'Sasarisa, three-minute timer', state: '✓ Timer', body: "I'll tell you in 3 minutes" },
  ];
  const $ = (s) => root.querySelector(s);
  const hud = $('.hud'), hs = $('.hs'), hh = $('.hh'), hb = $('.hb');
  const shots = {}; root.querySelectorAll('.scene').forEach((im) => { shots[im.dataset.k] = im; });
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const show = (k) => { Object.entries(shots).forEach(([n, im]) => { im.classList.toggle('on', n === k); im.classList.remove('dim'); }); };
  const card = (tone, state, heard, body) => {
    hud.classList.remove('amber', 'lime'); if (tone) hud.classList.add(tone);
    hs.textContent = state; hh.textContent = heard; hb.textContent = body;
  };
  if (matchMedia('(prefers-reduced-motion: reduce)').matches) {    // no motion: one finished example
    const c = scenes[0]; show(c.k); card('lime', c.state, c.say, c.body); return;
  }
  async function run() {
    for (let k = 0; ; k = (k + 1) % scenes.length) {
      const c = scenes[k];
      // 1) listening: the screen behind dims, the card turns blue and the words come in as they're said
      Object.values(shots).forEach((im) => im.classList.contains('on') && im.classList.add('dim'));
      root.classList.add('listening'); card('', ko ? '● 듣는 중' : '● Listening', '', '');
      const caret = document.createElement('i'); caret.className = 'caret';
      hb.append(caret);
      for (const ch of c.say) { caret.before(ch); await sleep(ko ? 62 : 34); }
      await sleep(420);
      root.classList.remove('listening');
      // 2) working (only for the slower ones, like the app)
      if (c.work) { card('amber', c.work, c.say, '…'); await sleep(950); }
      // 3) done: the screen is now that job, the card says so
      show(c.k); card('lime', c.state, c.say, c.body);
      hud.classList.add('pop'); setTimeout(() => hud.classList.remove('pop'), 350);
      await sleep(4200);
    }
  }
  // start when it's on screen
  let started = false;
  new IntersectionObserver((es) => { if (!started && es.some((e) => e.isIntersecting)) { started = true; run(); } }, { threshold: 0.2 }).observe(root);
  // the floating bar shows once the hero's own menu has scrolled away
  const bar = document.getElementById('nav'), bnav = document.querySelector('.hero .bnav');
  if (bar && bnav) new IntersectionObserver((es) => bar.classList.toggle('show', !es[0].isIntersecting)).observe(bnav);
})();
