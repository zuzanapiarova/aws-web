require("dotenv").config();
const express = require("express");
const cors = require("cors");

const app = express();

app.use(express.json());

// Enable CORS to allow only CloudFront domain
app.use(cors({
  origin: process.env.FRONTEND_ORIGIN, // CloudFront domain
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type']
}));

// Home routes "/"
app.get("/", (req, res) => {
  res.json({ message: "Hello from Node.js Backend at /!" });
});

// API routes now prefixed with "/api"
app.get("/api", (req, res) => {
  res.json({ message: "Hello from Node.js Backend at /api!" });
});

// Example: Add more API routes
app.get("/api/health", (req, res) => {
  res.json({ status: "OK", uptime: process.uptime() });
});

const PORT = process.env.PORT || 3000; // Default to port 3000 if not set
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));