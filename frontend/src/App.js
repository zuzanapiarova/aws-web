import logo from './logo.svg';
import './App.css';
import React, { useEffect, useState } from "react";
import axios from "axios";

function App() {
  const [response, setResponse] = useState("");

  const handleClick = () => {
    const apiUrl = process.env.REACT_APP_API_URL; // Ensure this matches the environment variable name
    console.log("Calling API at:", apiUrl); 
    axios.get(apiUrl) // this gets backend.net/api and passes the header
    .then((res) => {
      console.log(res.data);
      setResponse(res.data.message);
    })
    .catch((err) => {
      console.error(err);
      setResponse("Error connecting to backend.");
    });
  };

  return (
    <div style={{ padding: "2rem", fontFamily: "Arial" }}>
      <h1>Frontend to Backend Demo</h1>
      <button onClick={handleClick} style={{ padding: "0.5rem 1rem", fontSize: "1rem" }}>
        Get Message from Backend
      </button>
      <div style={{ marginTop: "1rem", fontSize: "1.2rem" }}>
        <strong>Response:</strong> {response}
      </div>
    </div>
  );
}

export default App;