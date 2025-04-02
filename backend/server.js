require("dotenv").config();
const express = require("express");
const cors = require("cors");

const app = express();
app.use(cors());

app.get("/", (req, res) => {
  res.json({ message: "Hello World from Node.js Backend!" });
});


const PORT = process.env.PORT; // bind port 3000 for the backend communication and requests 
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));