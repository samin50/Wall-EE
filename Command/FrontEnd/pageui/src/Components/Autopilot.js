import { useState } from 'react'
import Rover from './Rover';
import AddObstacles from './AddObstacles';


const Autopilot = () => {

  const [aliens, setAliens] = useState([]);

  const [intervalId, setIntervalId] = useState(0);

  const [coords, setCoords] = useState({
    xcoord:590,
    ycoord:90
  });


  const fetchObstacleData = async () => {
    try{

      const request = await fetch('http://35.176.71.115:8080/obstacles');
      const alienObj = await request.json();

    
      console.log("Alien location: " , alienObj);
      setAliens(alienObj);
      //setAliens((aliens) => [...aliens, alienObj]);

    }
    
    catch(err){
      console.log(err);
    }

  
  };

  const fetchCoordinateData = async () => {
    try{
      console.log('fetching..');

      const request = await fetch('http://35.176.71.115:8080/coordinates');
      const obj = await request.json();

      console.log("object is:", obj);

      setCoords(obj)
  

      if(obj.obstacle === 1){
        fetchObstacleData();
      }

      //console.log("object is:", obj);
    }

    catch(err){
      console.log(err);
    }
  
  };

  const start = async (event) => {
    await fetch('http://35.176.71.115:8080/autoPilot', {
      method: "POST",
      headers: {
        'Content-type': "application/json"
      },
      body: JSON.stringify({'mode': 3})
    });

    startTimer(event);
  };

  const startTimer = (event) => {

    if(intervalId) {
      clearInterval(intervalId);
          
      setIntervalId(0);
      return;
    }

  
    const newIntervalId = setInterval(fetchCoordinateData, 700);

    setIntervalId(newIntervalId);
  }

  const reset = () => {
    setAliens([]);
  }



  return (
    <div className="d-flex flex-row justify-content-evenly align-items-center" style={{minHeight: "93vh", maxHeight:"100vh", border:"4px solid orange"}}>

    <div className="h-5/6 w-4/6 relative border-2 border-black border-dashed" style={{width:'460px', height:'710px'}} >
      <Rover  Coordinates={coords}  />
      <AddObstacles Aliens={aliens} />

    </div>

    <button type="button" className="btn btn-success" onClick={start} > {intervalId ? "STOP" : "AutoPilot"} </button>
    <button type="button" className="btn btn-info" onClick={reset} > Reset </button>


    </div>
  )
}


export default Autopilot