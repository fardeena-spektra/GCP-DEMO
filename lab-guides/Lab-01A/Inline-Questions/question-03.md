### Question 3

Why is the agent deployed with its own service account and with Require authentication turned on?

- [x] So the service has only the access it needs and only authorised callers can reach it
- [ ] So the deployment finishes faster
- [ ] So the agent can use any bucket in the project
- [ ] So anyone on the internet can test it

**Explanation:** A dedicated least-privilege identity limits what the agent can access, and authentication keeps a banking service private.
