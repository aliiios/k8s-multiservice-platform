# ---- Build stage ----
FROM node:20-alpine AS builder

WORKDIR /app

# Copy only manifest files first — this maximizes Docker layer cache reuse.
# If only source code changes (not dependencies), this layer stays cached
# and npm install is skipped on rebuild, dramatically speeding up iteration.
COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY src/ ./src/

# ---- Runtime stage ----
FROM node:20-alpine

# Run as a non-root user. The 'node' image ships a built-in 'node' user
# (uid 1000) specifically for this purpose. Running containers as root is
# a well-known security anti-pattern — if an attacker achieves code execution
# inside the container, root-in-container is one privilege-escalation step
# closer to root-on-host (especially relevant given our SELinux/Docker
# discussion in Chapter 0).
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/src ./src
COPY package.json ./

USER node

EXPOSE 4001

# Using the array/exec form (not shell form) so Node receives OS signals
# (SIGTERM) directly. This matters enormously in Kubernetes: when a Pod is
# deleted, Kubernetes sends SIGTERM and waits up to terminationGracePeriodSeconds
# before SIGKILL. Shell-form CMD wraps the process so the signal goes to the
# shell instead of Node, breaking graceful shutdown — a subtle but very real
# production bug (Step 9/10 will build on this).
CMD ["node", "src/index.js"]
