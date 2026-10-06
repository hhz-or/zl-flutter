#!/usr/bin/env node
/**
 * 用 Chrome DevTools Protocol 给「指令」的 Web 产物截图。
 *
 * 之所以要单独写脚本：Flutter Web 渲染到 <canvas>，页面上没有可点的 DOM，
 * 只能用 CDP 派发真实鼠标事件，才能截到「已生成指令」和「设置弹窗」的状态。
 *
 * 用法：
 *   1) 另开一个终端启动静态服务器
 *        python -m http.server 8767 --directory build/web
 *   2) 以调试端口启动 Chrome（headless 也可以）
 *        chrome --headless=new --remote-debugging-port=9222 \
 *               --window-size=1280,900 --user-data-dir=<一次性目录> about:blank
 *      ⚠️ 一定要用**全新的** user-data-dir：应用把设置存在 localStorage，
 *         复用旧 profile 会让初始状态不是「未生成任何指令」。
 *   3) node tools/capture_screenshots.mjs http://127.0.0.1:8767/ docs/images
 *
 * 无任何第三方依赖：Node 18+ 自带 fetch，Node 22+ 自带 WebSocket。
 */

import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';

const url = process.argv[2] ?? 'http://127.0.0.1:8767/';
const outDir = process.argv[3] ?? 'docs/images';
const cdpBase = process.argv[4] ?? 'http://127.0.0.1:9222';

const VIEWPORT = { width: 1280, height: 900 };

// 坐标取自空态截图（页面没有导航栏，内容整体居中）。
const BUTTON = { x: 640, y: 520 }; // 「获取指令」
// 右上角齿轮：右侧 SafeArea + 12px padding，IconButton 最小命中区 40×40。
const SETTINGS_BUTTON = { x: 1248, y: 32 };
// 截图前把指针移到空白处，避免把 hover 态拍进去。
const NEUTRAL = { x: 200, y: 800 };

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function findPageTarget() {
  for (let attempt = 0; attempt < 30; attempt++) {
    try {
      const response = await fetch(`${cdpBase}/json/list`);
      const targets = await response.json();
      const page = targets.find(
        (target) => target.type === 'page' && target.webSocketDebuggerUrl,
      );
      if (page) {
        return page;
      }
    } catch {
      // Chrome 还没起来，继续等。
    }
    await sleep(500);
  }
  throw new Error(`连不上 CDP：${cdpBase}/json/list`);
}

function createClient(socketUrl) {
  const socket = new WebSocket(socketUrl);
  const pending = new Map();
  let nextId = 1;

  const ready = new Promise((resolve, reject) => {
    socket.addEventListener('open', () => resolve());
    socket.addEventListener('error', (event) => reject(event.error ?? event));
  });

  socket.addEventListener('message', (event) => {
    const message = JSON.parse(event.data);
    const entry = pending.get(message.id);
    if (!entry) return;
    pending.delete(message.id);
    if (message.error) {
      entry.reject(new Error(JSON.stringify(message.error)));
    } else {
      entry.resolve(message.result);
    }
  });

  const send = (method, params = {}) => {
    const id = nextId++;
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      socket.send(JSON.stringify({ id, method, params }));
    });
  };

  return { ready, send, close: () => socket.close() };
}

async function capture(client, name) {
  const { data } = await client.send('Page.captureScreenshot', {
    format: 'png',
    captureBeyondViewport: false,
  });
  const path = join(outDir, `${name}.png`);
  writeFileSync(path, Buffer.from(data, 'base64'));
  console.log(`已保存 ${path}`);
}

async function moveTo(client, x, y) {
  await client.send('Input.dispatchMouseEvent', {
    type: 'mouseMoved',
    x,
    y,
    button: 'none',
    buttons: 0,
  });
  await sleep(200);
}

async function click(client, x, y) {
  // 先移动再按下：Flutter 需要先收到 hover，tooltip / InkWell 才会进入激活态。
  await moveTo(client, x, y);
  await sleep(120);
  for (const type of ['mousePressed', 'mouseReleased']) {
    await client.send('Input.dispatchMouseEvent', {
      type,
      x,
      y,
      button: 'left',
      buttons: type === 'mousePressed' ? 1 : 0,
      clickCount: 1,
    });
    await sleep(60);
  }
}

const target = await findPageTarget();
const client = createClient(target.webSocketDebuggerUrl);
await client.ready;

await client.send('Page.enable');
await client.send('Emulation.setDeviceMetricsOverride', {
  ...VIEWPORT,
  deviceScaleFactor: 1,
  mobile: false,
});
await client.send('Page.navigate', { url });

// Flutter 首帧 + 字体加载；CanvasKit 冷启动在无缓存时可能要几秒。
await sleep(9000);
mkdirSync(outDir, { recursive: true });
await capture(client, 'home-empty');

// 点一次「获取指令」，先在乱码动画中途抓一帧，再等它播完。
await click(client, BUTTON.x, BUTTON.y);
await sleep(1100);
await capture(client, 'home-scrambling');
await sleep(5000);
await moveTo(client, NEUTRAL.x, NEUTRAL.y);
await capture(client, 'home-instruction');

// 打开右上角设置弹窗。
await click(client, SETTINGS_BUTTON.x, SETTINGS_BUTTON.y);
await sleep(1500);
await moveTo(client, NEUTRAL.x, NEUTRAL.y);
await capture(client, 'settings');

client.close();
console.log('全部截图完成。');
