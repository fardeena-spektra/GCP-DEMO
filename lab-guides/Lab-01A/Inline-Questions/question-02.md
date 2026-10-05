### Question 2

In the ADK Dev UI Events tab, what proves that an answer is grounded in the knowledge base?

- [ ] The answer is returned in under one second
- [ ] The answer mentions Northbridge Bank
- [x] A functionCall to get_product_info followed by a functionResponse before the final answer
- [ ] The chat shows the agent name Nova

**Explanation:** The functionCall and functionResponse events show the agent fetched the figure from the tool rather than from the model's general knowledge.
