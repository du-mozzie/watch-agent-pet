import { WebSocket, WebSocketServer } from 'ws';
import { randomBytes } from 'node:crypto';
import { once } from 'node:events';
import { PluginError } from '../../core/errors.js';

function connection(socket) {
  return {
    send(bytes) {
      if (socket.readyState !== WebSocket.OPEN) throw new PluginError('disconnected','WebSocket 已断开');
      if (socket.bufferedAmount > 65536) throw new PluginError('backpressure','WebSocket 队列已满');
      if (bytes.byteLength > 4096) throw new PluginError('invalid-message','消息过大');
      socket.send(bytes);
    },
    subscribeMessages(fn) {socket.on('message',fn); return ()=>socket.off('message',fn);},
    subscribeStatus(fn) {const cb=()=>fn('closed'); socket.on('close',cb); return ()=>socket.off('close',cb);},
    close() {socket.terminate();}
  };
}

/** A real socket pair limited to local simulator use, never a LAN watch listener. */
export async function websocketPair() {
  const token = randomBytes(32).toString('hex');
  const server = new WebSocketServer({host:'127.0.0.1',port:0,maxPayload:4096,
    verifyClient:({req})=>req.headers.authorization === `Bearer ${token}` && !req.headers.origin});
  let client;
  try {
    await once(server,'listening');
    const controller = new AbortController();
    const timeout = setTimeout(()=>controller.abort(),3000);
    try {
      const incoming = once(server,'connection',{signal:controller.signal});
      client = new WebSocket(`ws://127.0.0.1:${server.address().port}`,{headers:{Authorization:`Bearer ${token}`},maxPayload:4096});
      client.on('error',()=>{});
      const [[peer]] = await Promise.all([incoming,once(client,'open',{signal:controller.signal})]);
      peer.on('error',()=>{});
      let closed = false;
      return {desktop:connection(peer),device:connection(client),close() {
        if (closed) return; closed=true;
        peer.terminate(); client.terminate(); server.close();
      }};
    } finally { clearTimeout(timeout); }
  } catch (error) {
    client?.terminate(); for (const socket of server.clients) socket.terminate(); server.close(); throw error;
  }
}
export const loopbackWebsocket = {id:'loopback-websocket',name:'本机 WebSocket',apiVersion:1,create:()=>({open:websocketPair})};
