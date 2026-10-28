// End-to-end smoke tests: run against the deployed API, not a mock.
const api = Cypress.env("API_URL");

describe("visitor counter API", () => {
  before(() => {
    expect(api, "CYPRESS_API_URL must be set").to.be.a("string").and.not.be.empty;
  });

  it("GET returns JSON with a numeric count", () => {
    cy.request("GET", api).then((res) => {
      expect(res.status).to.eq(200);
      expect(res.headers["content-type"]).to.include("application/json");
      expect(res.body.count).to.be.a("number");
    });
  });

  it("POST increments the count by exactly one and persists it", () => {
    cy.request("GET", api).then((before) => {
      cy.request("POST", api).then((res) => {
        expect(res.status).to.eq(200);
        expect(res.body.count).to.eq(before.body.count + 1);
      });
      // a separate read proves the value was written to the database
      cy.request("GET", api).its("body.count").should("eq", before.body.count + 1);
    });
  });

  it("GET does not change the count", () => {
    cy.request("GET", api).then((a) => {
      cy.request("GET", api).its("body.count").should("eq", a.body.count);
    });
  });

  it("rejects unsupported methods", () => {
    cy.request({ method: "DELETE", url: api, failOnStatusCode: false })
      .its("status")
      .should("be.oneOf", [404, 405]);
  });
});
