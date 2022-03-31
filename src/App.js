import './App.css';
import { useEffect, useState } from 'react';
import { ethers } from 'ethers';


function App() {
  const provider = new ethers.providers.Web3Provider(window.ethereum)
  const signer = provider.getSigner()

  return (
    <h1>starter project</h1>
  );
}

export default App;
