// Election NUI logic — assets in html/assets/

const ASSETS = 'assets/';
const DEFAULT_PORTRAIT = ASSETS + 'portrait1.png';

const MOCK = [
  { id: 1, name: 'Sundance Kid', region_alias: 'new_hanover', portrait: ASSETS + 'portrait1.png', bio: 'A sharpshooter with a silver tongue.' },
  { id: 2, name: 'Billy the Kid', region_alias: 'new_hanover', portrait: ASSETS + 'portrait2.png', bio: 'Fast on the draw. Faster on decisions.' },
  { id: 3, name: 'Django',       region_alias: 'new_hanover', portrait: ASSETS + 'portrait3.png', bio: 'Tough as rawhide. Loyal to the town.' },
];

const el = {
  root:          document.getElementById('election'),
  regionTitle:   document.getElementById('regionTitle'),
  phase:         document.getElementById('phase'),

  modal:         document.getElementById('modal'),
  modalClose:    document.getElementById('modalClose'),
  modalPortrait: document.getElementById('modalPortrait'),
  modalName:     document.getElementById('modalName'),
  modalBio:      document.getElementById('modalBio'),
  modalRegion:   document.getElementById('modalRegion'),
  modalStatus:   document.getElementById('modalStatus'),
  voteBtn:       document.getElementById('voteBtn'),
  voteMsg:       document.getElementById('voteMsg'),
};

const resourceName = typeof GetParentResourceName === 'function'
  ? GetParentResourceName()
  : 'rsg-election';

let STATE = {
  candidates: [],
  hasVoted: false,
  phase: 'Idle'
};

function safeEl(e) { return e && typeof e === 'object'; }

function imgPath(p) {
  if (!p) return DEFAULT_PORTRAIT;
  return p.includes('/') ? p : ASSETS + p.replace(/\.jpg$/i, '.png');
}

/* ---------- ROOT VISIBILITY ---------- */

function showRoot() {
  if (!safeEl(el.root)) return;
  el.root.style.display = 'block';
  el.root.classList.remove('fade-out');
  el.root.classList.add('fade-in');
}

function hideRoot() {
  if (!safeEl(el.root)) return;
  el.root.classList.remove('fade-in');
  el.root.classList.add('fade-out');
  setTimeout(() => { el.root.style.display = 'none'; }, 200);
}

/* ---------- CANDIDATE SLOTS (3 frames) ---------- */

function updateSlots(list) {
  const slots = document.querySelectorAll('.slot');
  const candidates = (list || []).slice(0, slots.length);

  const phase = (STATE.phase || '').toLowerCase();
  const votingActive = phase === 'voting';

  slots.forEach((slot, i) => {
    const cand = candidates[i];
    const img  = slot.querySelector('.slot-frame') || slot.querySelector('img');
    const name = slot.querySelector('.slot-name');
    const vote = slot.querySelector('.btn.vote');

    if (!cand) {
      slot.dataset.candidateId = '';
      if (img)  img.src = DEFAULT_PORTRAIT;
      if (name) name.textContent = 'VACANT SLOT';
      if (vote) {
        vote.textContent = 'Awaiting Approval';
        vote.disabled = true;
        vote.dataset.candidateId = '';
      }
      return;
    }

    slot.dataset.candidateId = cand.id;
    if (img)  img.src = imgPath(cand.portrait);
    if (name) name.textContent = cand.name || 'Candidate';

    if (vote) {
      vote.textContent = votingActive ? 'View & Vote' : 'View';
      vote.disabled = false; // still clickable to view details
      vote.dataset.candidateId = cand.id;
    }
  });
}

/* ---------- MODAL ---------- */

function openModalByCandidateId(id) {
  const cands = STATE.candidates || [];
  const cand  = cands.find(c => String(c.id) === String(id));
  if (!cand || !safeEl(el.modal)) return;

  const phase = (STATE.phase || '').toLowerCase();
  const votingActive = phase === 'voting';

  if (el.modalPortrait) el.modalPortrait.src = imgPath(cand.portrait);
  if (el.modalName)     el.modalName.textContent = cand.name || 'Candidate';
  if (el.modalBio)      el.modalBio.textContent  = cand.bio || '—';
  if (el.modalRegion)   el.modalRegion.textContent = cand.region_alias || 'unknown';
  if (el.modalStatus)   el.modalStatus.textContent = cand.status || 'approved';

  if (el.voteMsg) {
    if (!votingActive) {
      el.voteMsg.textContent = 'Voting is not active. You can only view candidate details.';
    } else if (STATE.hasVoted) {
      el.voteMsg.textContent = 'You have already voted in this election.';
    } else {
      el.voteMsg.textContent = '';
    }
  }

  if (el.voteBtn) {
    if (votingActive && !STATE.hasVoted) {
      el.voteBtn.style.display = 'inline-block';
      el.voteBtn.disabled = false;
      el.voteBtn.dataset.candidateId = cand.id;
    } else {
      // Hide vote button outside voting phase or if already voted
      el.voteBtn.style.display = 'none';
    }
  }

  el.modal.classList.remove('hidden');
}

function closeModal() {
  if (safeEl(el.modal)) el.modal.classList.add('hidden');
}

/* ---------- NUI CLOSE (whole UI) ---------- */

function sendClose() {
  fetch(`https://${resourceName}/electionClose`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({})
  }).catch(() => {});
}

/* ---------- EVENT WIRING ---------- */

// confirm vote in modal
if (safeEl(el.voteBtn)) {
  el.voteBtn.addEventListener('click', () => {
    const candId = el.voteBtn.dataset.candidateId;
    if (!candId || STATE.hasVoted) return;

    fetch(`https://${resourceName}/electionVote`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8' },
      body: JSON.stringify({ candidateId: Number(candId) })
    }).catch(() => {});

    STATE.hasVoted = true;
    el.voteBtn.disabled = true;
    el.voteBtn.style.display = 'none';
    if (el.voteMsg) el.voteMsg.textContent = 'Your vote has been cast.';
  });
}

// close modal with X
if (safeEl(el.modalClose)) {
  el.modalClose.addEventListener('click', closeModal);
}

// click handler: frames + "View & Vote/View"
document.addEventListener('click', (e) => {
  // Vote/View button inside slot
  const voteBtn = e.target.closest('.slot .btn.vote');
  if (voteBtn) {
    const id = voteBtn.dataset.candidateId || voteBtn.closest('.slot')?.dataset.candidateId;
    if (id) openModalByCandidateId(id);
    return;
  }

  // Clicking the frame image itself
  const frameImg = e.target.closest('.slot .slot-frame');
  if (frameImg) {
    const slot = frameImg.closest('.slot');
    const id = slot && (slot.dataset.candidateId || slot.id?.replace('candidate', ''));
    if (id) openModalByCandidateId(id);
  }
});

// ESC: close modal if open, otherwise close whole UI
window.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;

  if (el.modal && !el.modal.classList.contains('hidden')) {
    closeModal();
  } else {
    sendClose();
  }
});

// X button on the main frame
document.getElementById('election-close')?.addEventListener('click', sendClose);

/* ---------- NUI MESSAGES FROM LUA ---------- */

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.type === 'election:toggle') {
    return data.display ? showRoot() : hideRoot();
  }

  if (data.type === 'election:update') {
    if (typeof data.regionTitle === 'string' && el.regionTitle) {
      el.regionTitle.textContent = data.regionTitle;
    }
    if (typeof data.phase === 'string') {
      STATE.phase = data.phase;
      if (el.phase) el.phase.textContent = data.phase;
    }
    if (typeof data.hasVoted === 'boolean') {
      STATE.hasVoted = data.hasVoted;
    }
    if (Array.isArray(data.candidates)) {
      STATE.candidates = data.candidates;
      updateSlots(STATE.candidates);
    }
  }
});

/* ---------- DEV PREVIEW (browser / file:) ---------- */

if (location.protocol === 'http:' || location.protocol === 'file:') {
  STATE.candidates = MOCK;
  STATE.hasVoted   = false;
  STATE.phase      = 'Voting';
  updateSlots(MOCK);
  setTimeout(showRoot, 50);
}
