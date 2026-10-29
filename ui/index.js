;(function () {
  'use strict'

  const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'zyrnex_music'
  const RECENT_KEY = 'zyrnex_music:recent'
  const VOLUME_KEY = 'zyrnex_music:volume'
  const RECENT_LIMIT = 5
  const SEEK_STEP = 10
  const ARC = 75.4

  const MODES = {
    car: { label: 'modeCar', icon: 'fa-solid fa-car' },
    radio: { label: 'modeRadio', icon: 'fa-solid fa-radio' },
    concert: { label: 'modeConcert', icon: 'fa-solid fa-microphone-lines' },
  }

  let t = {}

  const $ = (id) => document.getElementById(id)

  const el = {
    app: $('app'),
    modeIcon: $('mode-icon'),
    modeLabel: $('mode-label'),
    status: $('status'),
    eq: $('eq'),
    cover: $('cover'),
    coverImg: $('cover-img'),
    coverBlur: $('cover-blur'),
    title: $('title'),
    author: $('author'),
    timeline: $('timeline'),
    progress: $('progress'),
    progressFill: $('progress-fill'),
    timeNow: $('time-now'),
    timeTotal: $('time-total'),
    back: $('back'),
    toggle: $('toggle'),
    forward: $('forward'),
    stop: $('stop'),
    volume: $('volume'),
    volFill: $('vol-fill'),
    volValue: $('vol-value'),
    volIcon: $('vol-icon'),
    form: $('url-form'),
    url: $('url'),
    radiusRow: $('radius-row'),
    radius: $('radius'),
    radiusValue: $('radius-value'),
    recentWrap: $('recent-wrap'),
    recent: $('recent'),
    pick: $('pick'),
    rangeLabel: $('range-label'),
    recentLabel: $('recent-label'),
    pickLabel: $('pick-label'),
  }

  const state = {
    open: false,
    type: null,
    sound: null,
    loading: false,
    volume: 50,
    maxVolume: 100,
    time: 0,
    duration: 0,
    seeking: null,
    meta: null,
  }

  const metaCache = new Map()

  const post = (action, payload) =>
    fetch('https://' + RESOURCE + '/' + action, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=UTF-8' },
      body: JSON.stringify(payload || {}),
    }).catch(() => null)

  const store = {
    get(key, fallback) {
      try {
        const value = localStorage.getItem(key)
        return value === null ? fallback : JSON.parse(value)
      } catch (e) {
        return fallback
      }
    },
    set(key, value) {
      try {
        localStorage.setItem(key, JSON.stringify(value))
      } catch (e) {}
    },
  }

  const clamp = (value, min, max) => Math.min(max, Math.max(min, value))

  const formatTime = (seconds) => {
    if (!(seconds >= 0)) return '--:--'
    const s = Math.floor(seconds)
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    const sec = String(s % 60).padStart(2, '0')
    return h ? h + ':' + String(m).padStart(2, '0') + ':' + sec : String(m).padStart(2, '0') + ':' + sec
  }

  const youtubeId = (url) => {
    const match = /(?:youtube\.com\/(?:watch\?(?:.*&)?v=|shorts\/|embed\/|live\/)|youtu\.be\/)([\w-]{11})/i.exec(url || '')
    return match ? match[1] : null
  }

  const isUrl = (value) => /^https?:\/\/\S{4,}$/i.test(value) && value.length <= 512

  const fallbackMeta = (url) => {
    try {
      const parsed = new URL(url)
      const file = decodeURIComponent(parsed.pathname.split('/').filter(Boolean).pop() || parsed.hostname)
      return { title: file.replace(/\.[a-z0-9]{2,4}$/i, '').replace(/[_-]+/g, ' '), author: parsed.hostname.replace(/^www\./, ''), thumb: null }
    } catch (e) {
      return { title: url, author: '', thumb: null }
    }
  }

  const loadMeta = (url) => {
    if (metaCache.has(url)) return metaCache.get(url)

    const id = youtubeId(url)
    const base = id ? { title: 'YouTube', author: t.statusLoading, thumb: 'https://i.ytimg.com/vi/' + id + '/hqdefault.jpg' } : fallbackMeta(url)

    const promise = id
      ? fetch('https://www.youtube.com/oembed?format=json&url=' + encodeURIComponent('https://www.youtube.com/watch?v=' + id))
          .then((res) => (res.ok ? res.json() : null))
          .then((data) => (data ? { title: data.title, author: data.author_name, thumb: base.thumb } : { ...base, author: 'YouTube' }))
          .catch(() => ({ ...base, author: 'YouTube' }))
      : Promise.resolve(base)

    const entry = { base, promise }
    metaCache.set(url, entry)
    return entry
  }

  function renderMeta() {
    const sound = state.sound
    el.app.classList.toggle('has-sound', !!sound)

    if (!sound) {
      state.meta = null
      el.title.textContent = state.loading ? t.statusLoading : t.nothingPlaying
      el.author.textContent = state.loading ? '' : t.pasteHint
      el.cover.classList.remove('has-img')
      el.coverImg.removeAttribute('src')
      el.coverBlur.style.backgroundImage = ''
      return
    }

    const url = sound.url
    const { base, promise } = loadMeta(url)
    applyMeta(url, base)
    promise.then((meta) => {
      applyMeta(url, meta)
      addRecent(url, meta)
    })
  }

  function applyMeta(url, meta) {
    if (!state.sound || state.sound.url !== url) return
    state.meta = meta
    el.title.textContent = meta.title
    el.author.textContent = meta.author
    if (meta.thumb) {
      el.coverImg.src = meta.thumb
      el.coverBlur.style.backgroundImage = 'url("' + meta.thumb + '")'
      el.cover.classList.add('has-img')
    } else {
      el.cover.classList.remove('has-img')
      el.coverImg.removeAttribute('src')
      el.coverBlur.style.backgroundImage = ''
    }
  }

  function renderStatus() {
    const sound = state.sound
    const playing = !!sound && !sound.paused
    el.status.textContent = state.loading ? t.statusLoading : !sound ? t.statusIdle : sound.paused ? t.statusPaused : t.statusPlaying
    el.eq.classList.toggle('on', playing)
    el.toggle.innerHTML = playing ? '<i class="fa-solid fa-pause"></i>' : '<i class="fa-solid fa-play"></i>'
    el.stop.disabled = !sound
    renderTimeline()
  }

  function renderTimeline() {
    const known = !!state.sound && state.duration > 0
    el.timeline.classList.toggle('disabled', !known)
    el.back.disabled = !known
    el.forward.disabled = !known

    const time = state.seeking !== null ? state.seeking : state.time
    const ratio = known ? clamp(time / state.duration, 0, 1) : 0
    el.progressFill.style.width = ratio * 100 + '%'
    el.timeNow.textContent = state.sound ? formatTime(time) : '00:00'
    el.timeTotal.textContent = known ? formatTime(state.duration) : '--:--'
  }

  let volumeTimer = null

  function renderVolume() {
    const ratio = state.maxVolume ? state.volume / state.maxVolume : 0
    el.volFill.style.strokeDashoffset = ARC - ARC * ratio
    el.volValue.textContent = state.volume
    el.volume.classList.toggle('warn', ratio >= 0.85)
    el.volIcon.className = 'vol-icon fa-solid ' + (state.volume === 0 ? 'fa-volume-xmark' : ratio < 0.5 ? 'fa-volume-low' : 'fa-volume-high')
  }

  function setVolume(value) {
    const next = clamp(Math.round(value), 0, state.maxVolume)
    if (next === state.volume) return
    state.volume = next
    renderVolume()
    store.set(VOLUME_KEY, next)
    if (!state.sound) return
    clearTimeout(volumeTimer)
    volumeTimer = setTimeout(() => post('volume', { volume: state.volume / 100 }), 120)
  }

  function recentList() {
    const list = store.get(RECENT_KEY, [])
    return Array.isArray(list) ? list : []
  }

  function addRecent(url, meta) {
    const list = recentList().filter((item) => item.url !== url)
    list.unshift({ url, title: meta.title, author: meta.author, thumb: meta.thumb })
    store.set(RECENT_KEY, list.slice(0, RECENT_LIMIT))
    renderRecent()
  }

  function renderRecent() {
    const current = state.sound && state.sound.url
    const list = recentList().filter((item) => item.url !== current)
    el.recentWrap.classList.toggle('empty', !list.length)
    el.recent.innerHTML = ''

    list.forEach((item) => {
      const li = document.createElement('li')
      li.className = 'recent-item'

      const thumb = document.createElement('span')
      thumb.className = 'recent-thumb'
      if (item.thumb) thumb.style.backgroundImage = 'url("' + item.thumb + '")'
      else thumb.innerHTML = '<i class="fa-solid fa-music"></i>'

      const text = document.createElement('span')
      text.className = 'recent-text'
      const title = document.createElement('b')
      title.textContent = item.title || item.url
      const author = document.createElement('small')
      author.textContent = item.author || ''
      text.append(title, author)

      const play = document.createElement('i')
      play.className = 'fa-solid fa-play recent-play'

      li.append(thumb, text, play)
      li.addEventListener('click', () => play_(item.url))
      el.recent.appendChild(li)
    })
  }

  let loadingTimer = null

  function play_(url) {
    const value = (url || '').trim()
    if (!isUrl(value)) {
      el.form.classList.remove('shake')
      void el.form.offsetWidth
      el.form.classList.add('shake')
      return
    }
    state.loading = true
    state.time = 0
    state.duration = 0
    el.url.value = ''
    el.url.blur()
    renderStatus()
    if (!state.sound) renderMeta()
    post('play', { song: value, volume: state.volume / 100, radius: Number(el.radius.value) })
    clearTimeout(loadingTimer)
    loadingTimer = setTimeout(() => {
      if (!state.loading) return
      state.loading = false
      renderStatus()
      if (!state.sound) renderMeta()
    }, 4000)
  }

  function togglePlay() {
    if (state.sound) return post('pause')
    play_(el.url.value)
  }

  function seekBy(delta) {
    if (!state.sound || !(state.duration > 0)) return
    seekTo(state.time + delta)
  }

  function seekTo(time) {
    const target = clamp(Math.round(time), 0, Math.max(0, state.duration - 1))
    state.time = target
    renderTimeline()
    post('seek', { time: target })
  }

  function applySound(sound) {
    const previous = state.sound
    state.sound = sound || null
    state.loading = false
    if (!sound || !previous || previous.url !== sound.url) {
      state.time = 0
      state.duration = 0
    }
    if (sound && typeof sound.volume === 'number') {
      state.volume = clamp(Math.round(sound.volume * 100), 0, state.maxVolume)
      renderVolume()
    }
    if (sound && sound.radius) setRadius(sound.radius, false)
    renderMeta()
    renderStatus()
    renderRecent()
  }

  let radiusTimer = null

  function setRadius(value, send) {
    const next = clamp(Math.round(value), 1, Number(el.radius.max))
    el.radius.value = next
    el.radiusValue.textContent = next
    el.radius.style.setProperty('--fill', ((next - 1) / (Number(el.radius.max) - 1)) * 100 + '%')
    if (!send) return
    clearTimeout(radiusTimer)
    radiusTimer = setTimeout(() => post('radius', { radius: next }), 150)
  }

  function applyStrings(strings) {
    t = strings || t
    el.url.placeholder = t.urlPlaceholder || ''
    el.rangeLabel.textContent = t.range || ''
    el.recentLabel.textContent = t.recent || ''
    el.pickLabel.textContent = t.pick || ''
  }

  function open(data) {
    const mode = MODES[data.type] || MODES.car
    applyStrings(data.strings)
    state.open = true
    state.type = data.type
    state.maxVolume = Math.round((data.maxVolume || 1) * 100)
    state.volume = clamp(store.get(VOLUME_KEY, Math.round((data.defaultVolume || 0.5) * 100)), 0, state.maxVolume)
    state.sound = null
    state.seeking = null

    el.modeIcon.className = mode.icon
    el.modeLabel.textContent = t[mode.label] || ''
    el.app.dataset.mode = data.type
    el.radius.max = data.maxRadius || 300
    setRadius(data.radius || 50, false)

    renderVolume()
    applySound(data.state)
    el.app.classList.add('open')
    if (!data.state) setTimeout(() => el.url.focus(), 250)
  }

  function close() {
    state.open = false
    el.app.classList.remove('open')
    el.url.blur()
  }

  el.form.addEventListener('submit', (e) => {
    e.preventDefault()
    play_(el.url.value)
  })

  el.toggle.addEventListener('click', togglePlay)
  el.stop.addEventListener('click', () => state.sound && post('stop'))
  el.back.addEventListener('click', () => seekBy(-SEEK_STEP))
  el.forward.addEventListener('click', () => seekBy(SEEK_STEP))
  el.pick.addEventListener('click', () => post('pick'))
  el.radius.addEventListener('input', () => setRadius(el.radius.value, true))

  el.volume.addEventListener('wheel', (e) => {
    e.preventDefault()
    setVolume(state.volume + (e.deltaY < 0 ? 5 : -5))
  })

  el.volume.addEventListener('mousedown', (e) => {
    const startY = e.clientY
    const startVolume = state.volume
    const move = (ev) => setVolume(startVolume + (startY - ev.clientY) * 0.6)
    const up = () => {
      window.removeEventListener('mousemove', move)
      window.removeEventListener('mouseup', up)
    }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
  })

  const progressAt = (clientX) => {
    const rect = el.progress.getBoundingClientRect()
    return clamp((clientX - rect.left) / rect.width, 0, 1) * state.duration
  }

  el.progress.addEventListener('mousedown', (e) => {
    if (!state.sound || !(state.duration > 0)) return
    state.seeking = progressAt(e.clientX)
    renderTimeline()
    const move = (ev) => {
      state.seeking = progressAt(ev.clientX)
      renderTimeline()
    }
    const up = () => {
      window.removeEventListener('mousemove', move)
      window.removeEventListener('mouseup', up)
      const target = state.seeking
      state.seeking = null
      seekTo(target)
    }
    window.addEventListener('mousemove', move)
    window.addEventListener('mouseup', up)
  })

  document.addEventListener('keydown', (e) => {
    if (!state.open) return
    const typing = e.target === el.url

    if (e.key === 'Escape') {
      e.preventDefault()
      post('close')
      return
    }

    if (typing) return

    switch (e.key) {
      case ' ':
        togglePlay()
        break
      case 'ArrowUp':
        setVolume(state.volume + 5)
        break
      case 'ArrowDown':
        setVolume(state.volume - 5)
        break
      case 'ArrowLeft':
        seekBy(-SEEK_STEP)
        break
      case 'ArrowRight':
        seekBy(SEEK_STEP)
        break
      default:
        return
    }
    e.preventDefault()
  })

  document.addEventListener('paste', (e) => {
    if (!state.open || e.target === el.url) return
    const text = (e.clipboardData && e.clipboardData.getData('text')) || ''
    if (isUrl(text.trim())) {
      e.preventDefault()
      play_(text)
    }
  })

  window.addEventListener('message', ({ data }) => {
    if (!data) return

    switch (data.action) {
      case 'open':
        open(data)
        break
      case 'close':
        close()
        break
      case 'state':
        if (state.open) applySound(data.state)
        break
      case 'progress':
        if (!state.sound) return
        state.duration = data.duration > 0 ? data.duration : 0
        if (state.seeking === null) state.time = data.time >= 0 ? data.time : 0
        renderTimeline()
        break
    }
  })

  renderRecent()
})()
