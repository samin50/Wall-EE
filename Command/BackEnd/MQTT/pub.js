const mqtt = require("mqtt");
var client = mqtt.connect('mqtt://35.176.71.115');
var i = 0;
var location = {
    x: 100,
    y: 200,
    objectDetected: false
};
var direction = {direction: 1};
var battery = {battery: 0};
var z;
var alien = {
    color: -1,
    xcoorda:0,
    ycoorda:0
  };

var fan = {
    is_new: 1,
    xcoord: 0,
    ycoord:0
} 

var building = {
    is_new: 1,
    xcoord: 0,
    ycoord:0
}  

client.on("connect",function(){
    setInterval(function(){
        let z = Math.floor((Math.random() * 2));
        i = i+1;
        location = {
            xcoord:i,
            ycoord:i+10,
            obstacle: z
        };
        alien.color = 0;
        alien.xcoorda = i;
        alien.ycoorda = i;

        building.xcoord = i+50;
        building.ycoord = i+25;

        fan.xcoord = i+50;
        fan.ycoord = i+25;
        

        var random = Math.random()* 50;
        //setTimeout(() => {}, 1000);
        battery = {percentage: i};

        console.log(location); //random value to publish (until I get some actual data)
        console.log(direction);
        console.log(battery);
        console.log(alien);

        client.publish('location',JSON.stringify(location)); //publishing to topic test
        client.publish('battery',JSON.stringify(battery));
        client.publish('aliens',JSON.stringify(alien));
        client.publish('fans',JSON.stringify(fan));
        client.publish('buildings',JSON.stringify(building));

    },1000); //1 second interval between pubs
});
