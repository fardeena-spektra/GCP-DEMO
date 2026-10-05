### Question 1

Nova must never invent a rate or fee. Which part of the agent makes sure every figure comes from the approved knowledge base?

- [ ] The model name set in the agent
- [x] The get_product_info tool, together with the instruction that requires the agent to call it
- [ ] The Cloud Run service URL
- [ ] The region the agent is deployed to

**Explanation:** The tool reads the approved catalogue from Cloud Storage, and the instruction tells the agent to answer only from the tool's result.
