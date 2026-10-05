### Question 2

Which fix restores access while following least privilege?

- [ ] Grant the agent service account the Owner role on the project
- [ ] Make the bucket public
- [x] Grant roles/storage.objectViewer to the agent service account on the knowledge-base bucket only
- [ ] Grant Storage Admin to all users in the project

**Explanation:** Read-only access on one bucket gives the agent exactly what it needs and nothing more.
