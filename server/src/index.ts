import { DurableObject } from "cloudflare:workers";

export interface Env {
  ROOM: DurableObjectNamespace<Room>;
  ASSETS?: Fetcher;
}

const HOST_DROP_GRACE_SECONDS = 20;
const EMPTY_ROOM_GRACE_SECONDS = 120;

export const RATE_LIMITS = {
  TEXT_MAX_PER_5S: 6,
  IMAGE_MAX_PER_3S: 1,
  IMAGE_MAX_PER_MINUTE: 8,
  ACTIONS_MAX_PER_5S: 10,
};

interface Attachment {
  id: string;
  name: string;
  platform: "app" | "web";
  deviceId?: string;
}

interface MemberInfo {
  name: string;
  platform: "app" | "web";
  deviceId?: string;
  pendingUntil?: number;
}

interface ReplyQuote {
  id: string;
  name: string;
  preview: string;
}

export interface ChatMessage {
  id: string;
  clientId?: string;
  kind: "text" | "image" | "system";
  name: string;
  senderId?: string; // internal sender member id
  platform?: "app" | "web";
  text?: string;
  image?: string;
  reply?: ReplyQuote;
  deleted?: boolean;
  viewOnce?: boolean;
  recipients?: string[];
  viewedBy?: string[];
  openedBy?: string[];
  consumed?: boolean;
  ts: number;
}

interface MessageIndexItem {
  key: string;
  id: string;
  kind: "text" | "image" | "system";
}

interface DedupeItem {
  clientId: string;
  msgKey: string;
}

interface BannedData {
  memberIds: string[];
  deviceIds: string[];
}

interface RateLimitRecord {
  textTimestamps: number[];
  imageTimestamps: number[];
  actionTimestamps: number[];
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "*",
};

export class Room extends DurableObject<Env> {
  private rateLimitMap = new Map<string, RateLimitRecord>();

  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
  }

  private checkRateLimit(
    memberId: string,
    type: "text" | "image" | "action"
  ): { allowed: boolean; retryAfterMs: number } {
    const now = Date.now();
    let rec = this.rateLimitMap.get(memberId);
    if (!rec) {
      rec = { textTimestamps: [], imageTimestamps: [], actionTimestamps: [] };
      this.rateLimitMap.set(memberId, rec);
    }

    rec.textTimestamps = rec.textTimestamps.filter((t) => now - t < 5000);
    rec.actionTimestamps = rec.actionTimestamps.filter((t) => now - t < 5000);
    rec.imageTimestamps = rec.imageTimestamps.filter((t) => now - t < 60000);

    if (type === "text") {
      if (rec.textTimestamps.length >= RATE_LIMITS.TEXT_MAX_PER_5S) {
        const oldest = rec.textTimestamps[0];
        const retryAfterMs = Math.max(100, 5000 - (now - oldest));
        return { allowed: false, retryAfterMs };
      }
      rec.textTimestamps.push(now);
      return { allowed: true, retryAfterMs: 0 };
    }

    if (type === "image") {
      const recent3s = rec.imageTimestamps.filter((t) => now - t < 3000);
      if (recent3s.length >= RATE_LIMITS.IMAGE_MAX_PER_3S) {
        const oldest = recent3s[0];
        const retryAfterMs = Math.max(100, 3000 - (now - oldest));
        return { allowed: false, retryAfterMs };
      }
      if (rec.imageTimestamps.length >= RATE_LIMITS.IMAGE_MAX_PER_MINUTE) {
        const oldest = rec.imageTimestamps[0];
        const retryAfterMs = Math.max(100, 60000 - (now - oldest));
        return { allowed: false, retryAfterMs };
      }
      rec.imageTimestamps.push(now);
      return { allowed: true, retryAfterMs: 0 };
    }

    if (type === "action") {
      if (rec.actionTimestamps.length >= RATE_LIMITS.ACTIONS_MAX_PER_5S) {
        const oldest = rec.actionTimestamps[0];
        const retryAfterMs = Math.max(100, 5000 - (now - oldest));
        return { allowed: false, retryAfterMs };
      }
      rec.actionTimestamps.push(now);
      return { allowed: true, retryAfterMs: 0 };
    }

    return { allowed: true, retryAfterMs: 0 };
  }

  private getActiveSockets(excluding?: WebSocket): WebSocket[] {
    return this.ctx.getWebSockets().filter((s) => {
      if (excluding && s === excluding) return false;
      if (typeof s.readyState === "number" && s.readyState !== 1) return false;
      return true;
    });
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    if (url.pathname.endsWith("/test-alarm") && request.method === "POST") {
      await this.alarm();
      return new Response("OK", { headers: CORS_HEADERS });
    }

    if (url.pathname.endsWith("/exists")) {
      const isClosed = (await this.ctx.storage.get<boolean>("closed")) === true;
      if (isClosed) {
        return new Response(JSON.stringify({ exists: false }), {
          headers: {
            "Content-Type": "application/json",
            ...CORS_HEADERS,
          },
        });
      }

      const creatorId = await this.ctx.storage.get<string>("creatorId");
      if (!creatorId) {
        return new Response(JSON.stringify({ exists: false }), {
          headers: {
            "Content-Type": "application/json",
            ...CORS_HEADERS,
          },
        });
      }

      const sockets = this.getActiveSockets();
      const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
      const hasMembers = Object.keys(members).length > 0;
      const emptySince = await this.ctx.storage.get<number>("emptySince");

      let exists = false;
      if (sockets.length > 0) {
        exists = true;
      } else if (hasMembers) {
        exists = true;
      } else if (emptySince && Date.now() < emptySince + EMPTY_ROOM_GRACE_SECONDS * 1000) {
        exists = true;
      }

      return new Response(JSON.stringify({ exists }), {
        headers: {
          "Content-Type": "application/json",
          ...CORS_HEADERS,
        },
      });
    }

    if (url.pathname.endsWith("/ws")) {
      const isClosed = (await this.ctx.storage.get<boolean>("closed")) === true;
      const isCreateParam = url.searchParams.get("create") === "1";

      if (isClosed) {
        if (isCreateParam) {
          return new Response("Room is closed, choose another code", { status: 409, headers: CORS_HEADERS });
        }
        return new Response("Room not found", { status: 404, headers: CORS_HEADERS });
      }

      const id = url.searchParams.get("id");
      const rawName = url.searchParams.get("name") || "";
      const name = rawName.trim();
      const deviceId = url.searchParams.get("deviceId") || "";
      const rawPlatform = url.searchParams.get("platform");
      const platform: "app" | "web" = rawPlatform === "app" ? "app" : "web";

      // Check banned list
      const banned = (await this.ctx.storage.get<BannedData>("banned")) || { memberIds: [], deviceIds: [] };
      if ((id && banned.memberIds.includes(id)) || (deviceId && banned.deviceIds.includes(deviceId))) {
        return new Response("Forbidden", { status: 403, headers: CORS_HEADERS });
      }

      let creatorId = await this.ctx.storage.get<string>("creatorId");
      let members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
      const activeSockets = this.getActiveSockets();
      const roomExists = creatorId !== undefined || activeSockets.length > 0 || Object.keys(members).length > 0;

      if (!roomExists) {
        if (!isCreateParam) {
          return new Response("Room not found", { status: 404, headers: CORS_HEADERS });
        }
      }

      const upgradeHeader = request.headers.get("Upgrade");
      if (!upgradeHeader || upgradeHeader.toLowerCase() !== "websocket") {
        return new Response("Expected WebSocket", { status: 426, headers: CORS_HEADERS });
      }

      if (!id || name.length < 1 || name.length > 20) {
        return new Response("Invalid id or name", { status: 400, headers: CORS_HEADERS });
      }

      if (!roomExists) {
        creatorId = id;
        await this.ctx.storage.put("creatorId", creatorId);
      }

      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);

      const isRejoin = !!members[id];
      let assignedName: string;

      if (isRejoin) {
        assignedName = members[id].name;
        delete members[id].pendingUntil;
        members[id].platform = platform;
        if (deviceId) members[id].deviceId = deviceId;
      } else {
        assignedName = this.makeUniqueName(name, members);
        members[id] = { name: assignedName, platform, deviceId };
      }

      await this.ctx.storage.put("members", members);
      await this.ctx.storage.delete("emptySince");

      this.ctx.acceptWebSocket(server);
      const attachment: Attachment = { id, name: assignedName, platform, deviceId };
      server.serializeAttachment(attachment);

      // Send welcome
      server.send(
        JSON.stringify({
          type: "welcome",
          id,
          name: assignedName,
        })
      );

      // Send history_start
      server.send(JSON.stringify({ type: "history_start" }));

      // Replay stored messages
      const msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
      for (const item of msgIndex) {
        const m = await this.ctx.storage.get<ChatMessage>(item.key);
        if (m) {
          const publicMsg = this.formatPublicMsg(m, id);
          server.send(JSON.stringify(publicMsg));
        }
      }

      // Send history_end
      server.send(JSON.stringify({ type: "history_end" }));

      // Send members list to all connected sockets
      await this.broadcastMembers(this.ctx.getWebSockets(), members, creatorId);

      // If fresh join, announce "<name> entered the basement"
      if (!isRejoin) {
        const sysMsg: ChatMessage = {
          id: crypto.randomUUID(),
          kind: "system",
          name: assignedName,
          text: `${assignedName} entered the basement`,
          ts: Date.now(),
        };
        await this.saveAndBroadcast(sysMsg);
      }

      await this.syncAlarm();

      return new Response(null, { status: 101, webSocket: client });
    }

    return new Response("Not found", { status: 404, headers: CORS_HEADERS });
  }

  private makeUniqueName(baseName: string, members: Record<string, MemberInfo>): string {
    const existingNames = new Set(
      Object.values(members).map((m) => m.name.toLowerCase())
    );
    if (!existingNames.has(baseName.toLowerCase())) {
      return baseName;
    }
    let suffix = 2;
    while (existingNames.has(`${baseName} (${suffix})`.toLowerCase())) {
      suffix++;
    }
    return `${baseName} (${suffix})`;
  }

  private formatPublicMsg(m: ChatMessage, forMemberId?: string): Record<string, any> {
    const hasOpened = m.viewedBy ? m.viewedBy.includes(forMemberId || "") : false;
    const isMine = !!(forMemberId && m.senderId && m.senderId === forMemberId);
    return {
      type: "msg",
      id: m.id,
      clientId: m.clientId,
      kind: m.kind,
      name: m.name,
      mine: isMine,
      platform: m.platform,
      text: m.deleted ? undefined : m.text,
      image: (m.deleted || m.viewOnce || m.kind === "image") ? undefined : m.image,
      reply: m.deleted ? undefined : m.reply,
      deleted: m.deleted ? true : undefined,
      viewOnce: (m.kind === "image" || m.viewOnce) ? true : undefined,
      opened: m.viewOnce ? hasOpened : undefined,
      openedBy: m.openedBy,
      consumed: m.consumed ? true : undefined,
      ts: m.ts,
    };
  }

  private getOnlineMembers(
    sockets: WebSocket[],
    members: Record<string, MemberInfo>,
    creatorId?: string
  ): Array<{ id: string; name: string; host: boolean; platform: "app" | "web" }> {
    const connectedIds = new Set<string>();
    for (const ws of sockets) {
      try {
        const att = ws.deserializeAttachment() as Attachment | null;
        if (att?.id) {
          connectedIds.add(att.id);
        }
      } catch {}
    }
    const result: Array<{ id: string; name: string; host: boolean; platform: "app" | "web" }> = [];
    for (const id of connectedIds) {
      if (members[id]) {
        result.push({
          id,
          name: members[id].name,
          host: id === creatorId,
          platform: members[id].platform || "web",
        });
      }
    }
    return result;
  }

  private async broadcastMembers(
    sockets: WebSocket[],
    members: Record<string, MemberInfo>,
    creatorId?: string
  ): Promise<void> {
    const list = this.getOnlineMembers(sockets, members, creatorId);
    const payload = JSON.stringify({ type: "members", list });
    for (const s of sockets) {
      try {
        if (typeof s.readyState !== "number" || s.readyState === 1) {
          s.send(payload);
        }
      } catch {}
    }
  }

  async webSocketMessage(ws: WebSocket, message: string | ArrayBuffer): Promise<void> {
    if (typeof message !== "string") return;

    let parsed: any;
    try {
      parsed = JSON.parse(message);
    } catch {
      return;
    }

    if (!parsed || typeof parsed.type !== "string") return;

    const attachment = ws.deserializeAttachment() as Attachment | null;
    if (!attachment || !attachment.id || !attachment.name) return;

    const clientId = typeof parsed.clientId === "string" ? parsed.clientId : undefined;

    try {
      if (parsed.type === "leave") {
        await this.handleExplicitLeave(ws, attachment);
        return;
      }

      // =======================================================================
      // DELETE MESSAGE
      // =======================================================================
      if (parsed.type === "delete") {
        const rateCheck = this.checkRateLimit(attachment.id, "action");
        if (!rateCheck.allowed) {
          ws.send(JSON.stringify({ type: "error", reason: "slow_down", retryAfterMs: rateCheck.retryAfterMs }));
          return;
        }

        const msgId = parsed.id;
        if (typeof msgId !== "string") {
          ws.send(JSON.stringify({ type: "error", reason: "Invalid message id" }));
          return;
        }

        const msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
        const found = msgIndex.find((item) => item.id === msgId);
        if (!found) {
          ws.send(JSON.stringify({ type: "error", reason: "Message not found" }));
          return;
        }

        const targetMsg = await this.ctx.storage.get<ChatMessage>(found.key);
        if (!targetMsg) {
          ws.send(JSON.stringify({ type: "error", reason: "Message not found" }));
          return;
        }

        if (targetMsg.deleted) {
          ws.send(JSON.stringify({ type: "deleted", id: msgId }));
          return;
        }

        if (targetMsg.kind === "system") {
          ws.send(JSON.stringify({ type: "error", reason: "Cannot delete system message" }));
          return;
        }

        const creatorId = await this.ctx.storage.get<string>("creatorId");
        const isHost = attachment.id === creatorId;
        let isOwner = false;

        if (targetMsg.senderId) {
          isOwner = targetMsg.senderId === attachment.id;
        } else {
          const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
          const membersWithName = Object.entries(members).filter(([_, m]) => m.name.toLowerCase() === targetMsg.name.toLowerCase());
          if (membersWithName.length === 1 && membersWithName[0][0] === attachment.id) {
            isOwner = true;
          }
        }

        if (!isOwner && !isHost) {
          ws.send(JSON.stringify({ type: "error", reason: "Cannot delete this message" }));
          return;
        }

        try {
          targetMsg.deleted = true;
          delete targetMsg.text;
          delete targetMsg.image;
          delete targetMsg.reply;
          await this.ctx.storage.put(found.key, targetMsg);

          for (const item of msgIndex) {
            if (item.id === msgId) continue;
            const otherMsg = await this.ctx.storage.get<ChatMessage>(item.key);
            if (otherMsg && otherMsg.reply && otherMsg.reply.id === msgId) {
              otherMsg.reply.preview = "Message deleted";
              await this.ctx.storage.put(item.key, otherMsg);
            }
          }

          const delPayload = JSON.stringify({ type: "deleted", id: msgId });
          for (const s of this.getActiveSockets()) {
            try {
              s.send(delPayload);
            } catch {}
          }
        } catch (e) {
          console.error("Delete tombstone error:", e);
          ws.send(JSON.stringify({ type: "error", reason: "Failed to delete message" }));
        }
        return;
      }

      // =======================================================================
      // VIEW ONCE PHOTO: REQUEST IMAGE DATA
      // =======================================================================
      if (parsed.type === "view") {
        const rateCheck = this.checkRateLimit(attachment.id, "action");
        if (!rateCheck.allowed) {
          ws.send(JSON.stringify({ type: "error", reason: "slow_down", retryAfterMs: rateCheck.retryAfterMs }));
          return;
        }

        const msgId = parsed.id;
        if (typeof msgId !== "string") {
          ws.send(JSON.stringify({ type: "error", reason: "Invalid message id" }));
          return;
        }

        const msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
        const found = msgIndex.find((item) => item.id === msgId);
        if (!found) {
          ws.send(JSON.stringify({ type: "error", reason: "Photo no longer available" }));
          return;
        }

        const targetMsg = await this.ctx.storage.get<ChatMessage>(found.key);
        if (
          !targetMsg ||
          targetMsg.deleted ||
          !targetMsg.viewOnce ||
          targetMsg.consumed ||
          !targetMsg.image ||
          !targetMsg.recipients ||
          !targetMsg.recipients.includes(attachment.id) ||
          (targetMsg.viewedBy && targetMsg.viewedBy.includes(attachment.id)) ||
          targetMsg.senderId === attachment.id
        ) {
          ws.send(JSON.stringify({ type: "error", reason: "Photo no longer available" }));
          return;
        }

        // Send ONLY to the requester
        ws.send(JSON.stringify({ type: "view_data", id: msgId, image: targetMsg.image }));

        targetMsg.viewedBy = targetMsg.viewedBy || [];
        targetMsg.viewedBy.push(attachment.id);

        targetMsg.openedBy = targetMsg.openedBy || [];
        if (!targetMsg.openedBy.includes(attachment.name)) {
          targetMsg.openedBy.push(attachment.name);
        }

        const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
        const remainingUnviewed = targetMsg.recipients.filter(
          (rId) => !targetMsg.viewedBy!.includes(rId) && members[rId] !== undefined
        );

        if (remainingUnviewed.length === 0) {
          delete targetMsg.image;
          targetMsg.consumed = true;
        }

        await this.ctx.storage.put(found.key, targetMsg);

        // Broadcast viewed event
        const viewedPayload = JSON.stringify({
          type: "viewed",
          id: msgId,
          memberId: attachment.id,
          name: attachment.name,
        });
        for (const s of this.getActiveSockets()) {
          try {
            s.send(viewedPayload);
          } catch {}
        }
        return;
      }

      // =======================================================================
      // KICK MEMBER
      // =======================================================================
      if (parsed.type === "kick") {
        const rateCheck = this.checkRateLimit(attachment.id, "action");
        if (!rateCheck.allowed) {
          ws.send(JSON.stringify({ type: "error", reason: "slow_down", retryAfterMs: rateCheck.retryAfterMs }));
          return;
        }

        const creatorId = await this.ctx.storage.get<string>("creatorId");
        if (attachment.id !== creatorId) return;

        const targetId = parsed.id;
        if (typeof targetId !== "string" || targetId === creatorId) return;

        const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
        const targetMember = members[targetId];
        if (!targetMember) return;

        const allSockets = this.ctx.getWebSockets();
        for (const s of allSockets) {
          try {
            const a = s.deserializeAttachment() as Attachment | null;
            if (a?.id === targetId) {
              s.send(JSON.stringify({ type: "kicked", by: attachment.name }));
              s.close(4002, "Kicked");
            }
          } catch {}
        }

        delete members[targetId];
        await this.ctx.storage.put("members", members);

        const banned = (await this.ctx.storage.get<BannedData>("banned")) || { memberIds: [], deviceIds: [] };
        if (!banned.memberIds.includes(targetId)) {
          banned.memberIds.push(targetId);
        }
        if (targetMember.deviceId && !banned.deviceIds.includes(targetMember.deviceId)) {
          banned.deviceIds.push(targetMember.deviceId);
        }
        await this.ctx.storage.put("banned", banned);

        const kickMsg: ChatMessage = {
          id: crypto.randomUUID(),
          kind: "system",
          name: targetMember.name,
          text: `${targetMember.name} was kicked out`,
          ts: Date.now(),
        };
        await this.saveAndBroadcast(kickMsg);

        const remainingSockets = this.getActiveSockets();
        await this.broadcastMembers(remainingSockets, members, creatorId);
        await this.syncAlarm();
        return;
      }

      // =======================================================================
      // TEXT MESSAGE
      // =======================================================================
      if (parsed.type === "text") {
        const rateCheck = this.checkRateLimit(attachment.id, "text");
        if (!rateCheck.allowed) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "slow_down", retryAfterMs: rateCheck.retryAfterMs }));
          return;
        }

        if (typeof parsed.text !== "string") {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "Invalid text" }));
          return;
        }
        if (parsed.text.length < 1 || parsed.text.length > 2000) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "Text must be 1-2000 characters" }));
          return;
        }

        if (clientId) {
          const dedupeList = (await this.ctx.storage.get<DedupeItem[]>("dedupe")) || [];
          const existing = dedupeList.find((d) => d.clientId === clientId);
          if (existing) {
            const existingMsg = await this.ctx.storage.get<ChatMessage>(existing.msgKey);
            if (existingMsg) {
              const pub = this.formatPublicMsg(existingMsg, attachment.id);
              ws.send(JSON.stringify(pub));
              return;
            }
          }
        }

        let replyQuote: ReplyQuote | undefined;
        if (typeof parsed.replyTo === "string") {
          const msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
          const quoted = msgIndex.find((m) => m.id === parsed.replyTo);
          if (quoted) {
            const qMsg = await this.ctx.storage.get<ChatMessage>(quoted.key);
            if (qMsg && !qMsg.deleted) {
              const preview = (qMsg.kind === "image" || qMsg.viewOnce)
                ? "Photo"
                : (qMsg.text ? (qMsg.text.length > 80 ? qMsg.text.slice(0, 80) : qMsg.text) : "");
              replyQuote = {
                id: qMsg.id,
                name: qMsg.name,
                preview,
              };
            }
          }
        }

        const chatMsg: ChatMessage = {
          id: crypto.randomUUID(),
          clientId,
          kind: "text",
          name: attachment.name,
          senderId: attachment.id,
          platform: attachment.platform,
          text: parsed.text,
          reply: replyQuote,
          ts: Date.now(),
        };

        const msgKey = await this.saveAndBroadcast(chatMsg);

        if (clientId) {
          await this.addDedupe(clientId, msgKey);
        }
        return;
      }

      // =======================================================================
      // IMAGE MESSAGE (Standard or View Once)
      // =======================================================================
      if (parsed.type === "image") {
        const rateCheck = this.checkRateLimit(attachment.id, "image");
        if (!rateCheck.allowed) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "slow_down", retryAfterMs: rateCheck.retryAfterMs }));
          return;
        }

        if (typeof parsed.image !== "string") {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "Invalid image" }));
          return;
        }
        if (!parsed.image.startsWith("/9j/")) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "Image must be JPEG" }));
          return;
        }
        if (parsed.image.length > 900000) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "Image exceeds 900KB limit" }));
          return;
        }

        // ITEM 1: EVERY photo is view-once. The SERVER forces viewOnce: true on every image.
        const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
        const otherMemberIds = Object.keys(members).filter((mId) => mId !== attachment.id);
        if (otherMemberIds.length === 0) {
          ws.send(JSON.stringify({ type: "error", clientId, reason: "No one else is here" }));
          return;
        }
        const recipients = otherMemberIds;

        if (clientId) {
          const dedupeList = (await this.ctx.storage.get<DedupeItem[]>("dedupe")) || [];
          const existing = dedupeList.find((d) => d.clientId === clientId);
          if (existing) {
            const existingMsg = await this.ctx.storage.get<ChatMessage>(existing.msgKey);
            if (existingMsg) {
              const pub = this.formatPublicMsg(existingMsg, attachment.id);
              ws.send(JSON.stringify(pub));
              return;
            }
          }
        }

        let replyQuote: ReplyQuote | undefined;
        if (typeof parsed.replyTo === "string") {
          const msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
          const quoted = msgIndex.find((m) => m.id === parsed.replyTo);
          if (quoted) {
            const qMsg = await this.ctx.storage.get<ChatMessage>(quoted.key);
            if (qMsg && !qMsg.deleted) {
              const preview = "Photo";
              replyQuote = {
                id: qMsg.id,
                name: qMsg.name,
                preview,
              };
            }
          }
        }

        const chatMsg: ChatMessage = {
          id: crypto.randomUUID(),
          clientId,
          kind: "image",
          name: attachment.name,
          senderId: attachment.id,
          platform: attachment.platform,
          image: parsed.image,
          reply: replyQuote,
          viewOnce: true,
          recipients,
          viewedBy: [],
          openedBy: [],
          ts: Date.now(),
        };

        const msgKey = await this.saveAndBroadcast(chatMsg);

        if (clientId) {
          await this.addDedupe(clientId, msgKey);
        }
        return;
      }
    } catch (err: any) {
      console.error("webSocketMessage error:", err);
      try {
        ws.send(
          JSON.stringify({
            type: "error",
            clientId,
            reason: String(err?.message || err || "Failed to process message"),
          })
        );
      } catch {}
    }
  }

  private async addDedupe(clientId: string, msgKey: string): Promise<void> {
    try {
      let dedupeList = (await this.ctx.storage.get<DedupeItem[]>("dedupe")) || [];
      dedupeList.push({ clientId, msgKey });
      if (dedupeList.length > 200) {
        dedupeList = dedupeList.slice(dedupeList.length - 200);
      }
      await this.ctx.storage.put("dedupe", dedupeList);
    } catch (e) {
      console.error("addDedupe error:", e);
    }
  }

  private async handleExplicitLeave(ws: WebSocket, attachment: Attachment): Promise<void> {
    const creatorId = await this.ctx.storage.get<string>("creatorId");
    const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
    const memberName = members[attachment.id]?.name || attachment.name;

    if (attachment.id === creatorId) {
      await this.closeRoom(memberName);
      return;
    }

    delete members[attachment.id];
    await this.ctx.storage.put("members", members);

    const leaveMsg: ChatMessage = {
      id: crypto.randomUUID(),
      kind: "system",
      name: memberName,
      text: `${memberName} left the basement`,
      ts: Date.now(),
    };
    await this.saveAndBroadcast(leaveMsg);

    try {
      ws.close(1000, "Left");
    } catch {}

    const remainingSockets = this.getActiveSockets(ws);
    if (remainingSockets.length === 0) {
      const existingEmptySince = await this.ctx.storage.get<number>("emptySince");
      if (!existingEmptySince) {
        await this.ctx.storage.put("emptySince", Date.now());
      }
    }

    await this.broadcastMembers(remainingSockets, members, creatorId);
    await this.syncAlarm(ws);
  }

  async webSocketClose(ws: WebSocket, code: number, reason: string, wasClean: boolean): Promise<void> {
    try {
      const att = ws.deserializeAttachment() as Attachment | null;
      const creatorId = await this.ctx.storage.get<string>("creatorId");

      if (code === 4000) {
        if (att && att.id === creatorId) {
          await this.closeRoom(att.name);
          return;
        }
        if (att) {
          await this.handleExplicitLeave(ws, att);
          return;
        }
      }

      await this.handleSocketDisconnect(ws);
    } catch (e) {
      console.error("webSocketClose error:", e);
    }
  }

  async webSocketError(ws: WebSocket, error: unknown): Promise<void> {
    await this.handleSocketDisconnect(ws);
  }

  private async handleSocketDisconnect(closingWs: WebSocket): Promise<void> {
    try {
      const isClosed = (await this.ctx.storage.get<boolean>("closed")) === true;
      if (isClosed) return;

      const att = closingWs.deserializeAttachment() as Attachment | null;
      const remainingSockets = this.getActiveSockets(closingWs);
      const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
      const creatorId = await this.ctx.storage.get<string>("creatorId");

      if (att?.id && members[att.id]) {
        const hasOtherSockets = remainingSockets.some((s) => {
          try {
            const a = s.deserializeAttachment() as Attachment | null;
            return a?.id === att.id;
          } catch {
            return false;
          }
        });

        if (!hasOtherSockets) {
          const graceSeconds = att.id === creatorId ? HOST_DROP_GRACE_SECONDS : 20;
          members[att.id].pendingUntil = Date.now() + graceSeconds * 1000;
          await this.ctx.storage.put("members", members);
        }
      }

      if (remainingSockets.length === 0) {
        const existingEmptySince = await this.ctx.storage.get<number>("emptySince");
        if (!existingEmptySince) {
          await this.ctx.storage.put("emptySince", Date.now());
        }
      }

      await this.broadcastMembers(remainingSockets, members, creatorId);
      await this.syncAlarm(closingWs);
    } catch (e) {
      console.error("handleSocketDisconnect error:", e);
    }
  }

  async alarm(): Promise<void> {
    try {
      const isClosed = (await this.ctx.storage.get<boolean>("closed")) === true;
      if (isClosed) {
        await this.ctx.storage.deleteAll();
        return;
      }

      const now = Date.now();
      const creatorId = await this.ctx.storage.get<string>("creatorId");
      const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};

      if (creatorId && members[creatorId]?.pendingUntil && members[creatorId].pendingUntil! <= now) {
        const creatorName = members[creatorId].name;
        await this.closeRoom(creatorName);
        return;
      }

      let membersChanged = false;

      for (const [id, m] of Object.entries(members)) {
        if (id !== creatorId && m.pendingUntil && m.pendingUntil <= now) {
          delete members[id];
          membersChanged = true;

          const leaveMsg: ChatMessage = {
            id: crypto.randomUUID(),
            kind: "system",
            name: m.name,
            text: `${m.name} left the basement`,
            ts: now,
          };
          await this.saveAndBroadcast(leaveMsg);
        }
      }

      if (membersChanged) {
        await this.ctx.storage.put("members", members);
      }

      const sockets = this.getActiveSockets();
      await this.broadcastMembers(sockets, members, creatorId);

      const pendingCount = Object.values(members).filter((m) => m.pendingUntil).length;

      if (sockets.length === 0 && pendingCount === 0) {
        const emptySince = await this.ctx.storage.get<number>("emptySince");
        if (emptySince && now >= emptySince + EMPTY_ROOM_GRACE_SECONDS * 1000) {
          await this.ctx.storage.deleteAll();
          return;
        }
      }

      await this.syncAlarm();
    } catch (e) {
      console.error("alarm handler error:", e);
    }
  }

  private async syncAlarm(excluding?: WebSocket): Promise<void> {
    try {
      const isClosed = (await this.ctx.storage.get<boolean>("closed")) === true;
      if (isClosed) return;

      const now = Date.now();
      const members = (await this.ctx.storage.get<Record<string, MemberInfo>>("members")) || {};
      const sockets = this.getActiveSockets(excluding);

      let earliestDeadline: number | null = null;

      for (const m of Object.values(members)) {
        if (m.pendingUntil) {
          if (earliestDeadline === null || m.pendingUntil < earliestDeadline) {
            earliestDeadline = m.pendingUntil;
          }
        }
      }

      if (sockets.length === 0) {
        let emptySince = await this.ctx.storage.get<number>("emptySince");
        if (!emptySince) {
          emptySince = now;
          await this.ctx.storage.put("emptySince", emptySince);
        }
        const emptyDeadline = emptySince + EMPTY_ROOM_GRACE_SECONDS * 1000;
        if (earliestDeadline === null || emptyDeadline < earliestDeadline) {
          earliestDeadline = emptyDeadline;
        }
      } else {
        await this.ctx.storage.delete("emptySince");
      }

      if (earliestDeadline !== null) {
        const targetTime = Math.max(earliestDeadline, now + 100);
        await this.ctx.storage.setAlarm(targetTime);
      } else {
        await this.ctx.storage.deleteAlarm();
      }
    } catch (e) {
      console.error("syncAlarm error:", e);
    }
  }

  private async closeRoom(byName: string): Promise<void> {
    try {
      const sockets = this.ctx.getWebSockets();
      const payload = JSON.stringify({ type: "room_closed", by: byName });

      for (const s of sockets) {
        try {
          s.send(payload);
        } catch {}
      }

      for (const s of sockets) {
        try {
          s.close(4001, "room closed");
        } catch {}
      }

      await this.ctx.storage.deleteAll();
      await this.ctx.storage.deleteAlarm();

      await this.ctx.storage.put("closed", true);
      await this.ctx.storage.setAlarm(Date.now() + 10 * 60 * 1000);
    } catch (e) {
      console.error("closeRoom error:", e);
    }
  }

  private async saveAndBroadcast(msg: ChatMessage): Promise<string> {
    try {
      let seq = (await this.ctx.storage.get<number>("seq")) || 0;
      seq++;
      await this.ctx.storage.put("seq", seq);

      const msgKey = "m:" + String(seq).padStart(8, "0");
      await this.ctx.storage.put(msgKey, msg);

      let msgIndex = (await this.ctx.storage.get<MessageIndexItem[]>("msg_index")) || [];
      msgIndex.push({ key: msgKey, id: msg.id, kind: msg.kind });

      const keysToDelete: string[] = [];

      // Keep only latest 100 messages total
      if (msgIndex.length > 100) {
        const excessCount = msgIndex.length - 100;
        const removed = msgIndex.splice(0, excessCount);
        for (const item of removed) {
          keysToDelete.push(item.key);
        }
      }

      // Keep only latest 15 image messages
      const imageItems = msgIndex.filter((item) => item.kind === "image");
      if (imageItems.length > 15) {
        const excessImages = imageItems.length - 15;
        const removedImages = imageItems.slice(0, excessImages);
        for (const r of removedImages) {
          const idx = msgIndex.findIndex((it) => it.key === r.key);
          if (idx !== -1) {
            msgIndex.splice(idx, 1);
            if (!keysToDelete.includes(r.key)) {
              keysToDelete.push(r.key);
            }
          }
        }
      }

      await this.ctx.storage.put("msg_index", msgIndex);

      for (const k of keysToDelete) {
        try {
          await this.ctx.storage.delete(k);
        } catch {}
      }

      const sockets = this.getActiveSockets();
      for (const s of sockets) {
        try {
          const att = s.deserializeAttachment() as Attachment | null;
          const pub = this.formatPublicMsg(msg, att?.id);
          s.send(JSON.stringify(pub));
        } catch {}
      }

      return msgKey;
    } catch (e) {
      console.error("saveAndBroadcast error:", e);
      throw e;
    }
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const match = url.pathname.match(/^\/room\/([0-9]{5})(\/.*)?$/);
    if (match) {
      const code = match[1];
      const subpath = match[2] || "";

      if (subpath === "/exists" || subpath === "/ws" || subpath === "/test-alarm") {
        const id = env.ROOM.idFromName(code);
        const room = env.ROOM.get(id);
        return room.fetch(request);
      }
      return new Response("Not found", { status: 404, headers: CORS_HEADERS });
    }

    if (env.ASSETS) {
      return env.ASSETS.fetch(request);
    }

    return new Response("Not found", { status: 404, headers: CORS_HEADERS });
  },
};
