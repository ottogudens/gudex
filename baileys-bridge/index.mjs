import express from 'express';
import makeWASocket, {
  DisconnectReason,
  fetchLatestBaileysVersion,
  useMultiFileAuthState,
} from '@whiskeysockets/baileys';
import pino from 'pino';
import QRCode from 'qrcode';
import { mkdir, rm } from 'node:fs/promises';
import path from 'node:path';

const app = express();
app.use(express.json({ limit: '32kb' }));

const port = Number(process.env.PORT || 3000);
const bridgeToken = process.env.BAILEYS_BRIDGE_TOKEN;
const testEnabled = process.env.BAILEYS_TEST_ENABLED === 'true';
const authDir = process.env.BAILEYS_AUTH_DIR || '/data/baileys-auth';
const allowedRecipients = new Set(
  (process.env.BAILEYS_TEST_RECIPIENTS || '').split(',').map((value) => value.replace(/\D/g, '')).filter(Boolean),
);

let socket;
let status = 'disconnected';
let phone = null;
let qr = null;
let connecting = null;
let connectionGeneration = 0;
let reconnectTimer;
let restartAttempts = 0;
const maxRestartAttempts = 3;

function internalOnly(request, response, next) {
  if (!bridgeToken || request.get('x-gudex-bridge-token') !== bridgeToken) {
    return response.status(401).json({ detail: 'Unauthorized bridge request' });
  }
  return next();
}

function publicStatus() {
  return {
    status,
    connected: status === 'connected',
    phone,
    // This is only delivered via the backend's administrator-only endpoint.
    qr: qr || null,
    testEnabled,
    allowlistedRecipients: allowedRecipients.size,
  };
}

function resetPublicState(nextStatus = 'disconnected') {
  socket = undefined;
  connecting = null;
  if (reconnectTimer) clearTimeout(reconnectTimer);
  reconnectTimer = undefined;
  restartAttempts = 0;
  status = nextStatus;
  phone = null;
  qr = null;
}

function validatedAuthDir() {
  const resolved = path.resolve(authDir);
  // BAILEYS_AUTH_DIR holds only a disposable test session. Still, never allow
  // an incorrectly configured value to erase a filesystem root.
  if (resolved === path.parse(resolved).root || resolved.length < 5) {
    throw new Error('BAILEYS_AUTH_DIR no es un directorio seguro para reiniciar la sesión');
  }
  return resolved;
}

async function resetSession() {
  const previousSocket = socket;
  connectionGeneration += 1;
  resetPublicState();
  try {
    previousSocket?.end?.(new Error('La sesión de pruebas fue reiniciada por un administrador'));
  } catch {
    // The old connection is already invalidated by connectionGeneration.
  }
  const directory = validatedAuthDir();
  await rm(directory, { recursive: true, force: true });
  await mkdir(directory, { recursive: true });
  return publicStatus();
}

function schedulePostScanReconnect(generation) {
  if (generation !== connectionGeneration || reconnectTimer || restartAttempts >= maxRestartAttempts) return;
  restartAttempts += 1;
  status = 'reconnecting';
  qr = null;
  phone = null;
  // Baileys emits restartRequired (515) after a QR is accepted. The new
  // credentials have already been persisted by creds.update; reconnecting is
  // required to complete the pairing and obtain the "open" event.
  reconnectTimer = setTimeout(async () => {
    reconnectTimer = undefined;
    if (generation !== connectionGeneration) return;
    try {
      await connect({ resetInvalidSession: false });
    } catch (error) {
      // Do not expose auth data, QR contents, or phone numbers in logs.
      console.error('Baileys reconnect after QR failed:', error?.message || 'unknown error');
      if (generation === connectionGeneration) status = 'disconnected';
    }
  }, 500);
}

async function connect({ resetInvalidSession = true } = {}) {
  if (status === 'connected') return publicStatus();
  // A logged-out credential set cannot emit a new QR. Remove only the bridge's
  // own persisted auth directory before starting a fresh WhatsApp session.
  if (status === 'logged_out' && resetInvalidSession) await resetSession();
  if (connecting) return connecting;
  const generation = ++connectionGeneration;
  connecting = (async () => {
    status = 'connecting';
    qr = null;
    phone = null;
    const { state, saveCreds } = await useMultiFileAuthState(authDir);
    const { version } = await fetchLatestBaileysVersion();
    socket = makeWASocket({
      auth: state,
      version,
      printQRInTerminal: false,
      browser: ['Gudex Testing', 'Chrome', '1.0.0'],
      logger: pino({ level: 'silent' }),
      markOnlineOnConnect: false,
      syncFullHistory: false,
    });
    socket.ev.on('creds.update', (...args) => {
      if (generation === connectionGeneration) saveCreds(...args);
    });
    socket.ev.on('connection.update', async (update) => {
      if (generation !== connectionGeneration) return;
      if (update.qr) {
        qr = update.qr;
        status = 'awaiting_qr_scan';
      }
      if (update.connection === 'open') {
        phone = socket?.user?.id?.split(':')[0]?.split('@')[0] || null;
        qr = null;
        status = 'connected';
        restartAttempts = 0;
      }
      if (update.connection === 'close') {
        const code = update.lastDisconnect?.error?.output?.statusCode ?? update.lastDisconnect?.error?.statusCode;
        socket = undefined;
        qr = null;
        phone = null;
        if (code === DisconnectReason.loggedOut) {
          status = 'logged_out';
        } else if (code === DisconnectReason.restartRequired) {
          schedulePostScanReconnect(generation);
        } else {
          status = 'disconnected';
        }
      }
    });
    return publicStatus();
  })();
  try {
    return await connecting;
  } finally {
    connecting = null;
  }
}

app.get('/health', (_request, response) => response.json({ ok: true, testEnabled }));

app.get('/session/status', internalOnly, (_request, response) => response.json(publicStatus()));
app.post('/session/connect', internalOnly, async (_request, response, next) => {
  if (!testEnabled) return response.status(409).json({ detail: 'Baileys test mode is disabled' });
  try {
    await connect();
    // QR arrives asynchronously; the admin client polls status while pairing.
    return response.status(202).json(publicStatus());
  } catch (error) {
    return next(error);
  }
});

app.post('/session/reset', internalOnly, async (_request, response, next) => {
  if (!testEnabled) return response.status(409).json({ detail: 'Baileys test mode is disabled' });
  try {
    await resetSession();
    await connect({ resetInvalidSession: false });
    // QR arrives asynchronously; the administrator polls /session/status.
    return response.status(202).json(publicStatus());
  } catch (error) {
    return next(error);
  }
});

app.post('/messages/test', internalOnly, async (request, response) => {
  if (!testEnabled) return response.status(409).json({ detail: 'Baileys test mode is disabled' });
  if (status !== 'connected' || !socket) return response.status(409).json({ detail: 'No active Baileys session' });
  const to = String(request.body?.phone || '').replace(/\D/g, '');
  const text = String(request.body?.message || '').trim();
  if (!/^\d{8,15}$/.test(to) || !text || text.length > 1000) {
    return response.status(422).json({ detail: 'Invalid test recipient or message' });
  }
  if (allowedRecipients.size === 0 || !allowedRecipients.has(to)) {
    return response.status(403).json({ detail: 'Recipient is not in BAILEYS_TEST_RECIPIENTS' });
  }
  await socket.sendMessage(`${to}@s.whatsapp.net`, { text });
  return response.status(202).json({ accepted: true, recipient: to });
});

app.use((error, _request, response, _next) => {
  // Do not log QR data, auth files, tokens, phone numbers or message bodies.
  console.error('Baileys bridge operation failed:', error?.message || 'unknown error');
  response.status(500).json({ detail: 'Baileys bridge operation failed' });
});

if (!bridgeToken) {
  console.error('BAILEYS_BRIDGE_TOKEN is required');
  process.exit(1);
}
app.listen(port, () => console.log(`Gudex Baileys test bridge listening on ${port}`));
