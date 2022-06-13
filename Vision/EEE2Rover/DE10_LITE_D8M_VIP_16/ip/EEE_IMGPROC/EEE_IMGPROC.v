module EEE_IMGPROC(
	// global clock & reset
	clk,
	reset_n,
	
	// mm slave
	s_chipselect,
	s_read,
	s_write,
	s_readdata,
	s_writedata,
	s_address,

	// stream sink
	sink_data,
	sink_valid,
	sink_ready,
	sink_sop,
	sink_eop,
	
	// streaming source
	source_data,
	source_valid,
	source_ready,
	source_sop,
	source_eop,
	
	// conduit
	mode,

	//VSPI interface
	avalon_master_read,
	avalon_master_write, //assert when putting out data
	avalon_to_SPI, //data goes through here
	avalon_from_SPI,
	avalon_spi_addr,
	avalon_spi_select,
	avalon_master_waitrequest
);


// global clock & reset
input	clk;
input	reset_n;

// mm slave
input							s_chipselect;
input							s_read;
input							s_write;
output	reg	[31:0]	s_readdata;
input	[31:0]				s_writedata;
input	[2:0]					s_address;


// streaming sink
input	[23:0]            	sink_data;
input								sink_valid;
output							sink_ready;
input								sink_sop;
input								sink_eop;

// streaming source
output	[23:0]			  	   source_data;
output								source_valid;
input									source_ready;
output								source_sop;
output								source_eop;

// conduit export
input                         mode; //externally connected to switch 0

//SPI interface
output	reg						avalon_master_write;
output 	reg						avalon_master_read;
output	reg [15:0]				avalon_to_SPI;
input			[15:0]	avalon_from_SPI;
output	reg [4:0]					avalon_spi_addr;
output reg avalon_spi_select;
input avalon_master_waitrequest;

////////////////////////////////////////////////////////////////////////
//
parameter IMAGE_W = 11'd640;
parameter IMAGE_H = 11'd480;
parameter MESSAGE_BUF_MAX = 256;
parameter MSG_INTERVAL = 6;
parameter BB_COL_DEFAULT = 24'h00ff00;


wire [7:0]   red, green, blue, gray;
wire [7:0]   red_out, green_out, blue_out;
wire         sop, eop, in_valid, out_ready;
reg [23:0] colourOutput;
//assign {red_out, green_out, blue_out} = (mode & ~sop & packet_video)? {newRed, newGreen, newBlue} : {red,green,blue};
assign {red_out, green_out, blue_out} = (mode & ~sop & packet_video)? colourOutput : {red,green,blue};
//HSV calculations
wire [8:0] Hue;
wire [15:0] Saturation;
wire [7:0] maxVal, minVal, Value, delta;
wire isRedMax, isGreenMax, isBlueMax;
wire isRedMin, isGreenMin, isBlueMin;

//reg [24:0] dataBuffer[639:0][2:0] ;//This contains the data of the last three rows in the image in HSV *(9 + 8 + 8 = 25)
reg [23:0] runningValueTotal;
wire [15:0] zPartial, zPartial2, zPartial3, mHSV;
wire [13:0] HRed, HGreen, HBlue;
reg [8:0] finalHue, zmSum;
wire [8:0] outputHue;
wire [7:0] outputSat, outputVal, newRed, newGreen, newBlue;
reg [7:0] finalSat, finalVal;
reg [10:0] x, y;
////////////////////////////////////////////////////////////////////////

assign gray = green[7:1] + red[7:2] + blue[7:2]; //Grey = green/2 + red/4 + blue/4 (average of all colours to produce grayscale)
//Pixels enter sequentially

//Convert to HSV:
//Max value
assign isRedMax = ((red > blue) && (red > green)) ? 1 : 0; //One bit
assign isGreenMax = ((green > blue) && (green > red)) ? 1 : 0;
assign isBlueMax = ((blue > red) && (blue > green)) ? 1 : 0;
assign maxVal = isRedMax ? red : (isBlueMax ? blue : green);
//Min val
assign isRedMin = ((red < blue) && (red < green)) ? 1 : 0; //One bit
assign isGreenMin = ((green < blue) && (green < red)) ? 1 : 0;
assign isBlueMin = ((blue < red) && (blue < green)) ? 1 : 0;
assign minVal = isRedMin ? red : (isBlueMin ? blue : green);
//Intermediate values
assign delta = maxVal-minVal; //8 bits
//RGB to HSV calculations - Assume correct
// assign HRed = ((delta == 0) || (((green-blue) % 6) == 0) || (((blue-green) % 6) == 0)) ? 14'd0 : 
// ((green < blue) ? (60*(((green-blue)/delta) % 6)) : (60*(6-((blue-green)/delta) % 6))); //Max 14 bits
// assign HGreen = (delta == 0) ? 14'd0 :
// ((blue > red) ? (((60 *(blue-red))/delta) + 120) : (120 - ((60 *(red-blue))/delta)));
// assign HBlue = (delta == 0) ? 14'd0 : 
// ((red > green) ? (((60 *(red-green))/delta) + 240) : (240 - ((60 *(green-red))/delta)));
assign Hue = (delta == 0) ? 14'd0 :
((isRedMax && isBlueMin) ? ((60*(green-blue))/delta) :
((isGreenMax && isBlueMin) ? (60+((60*(red-blue))/delta)) :
((isGreenMax && isRedMin) ? (120+((60*(blue-red))/delta)) :
((isBlueMax && isRedMin) ? (180+((60*(green-red))/delta)) :
((isBlueMax && isGreenMin) ? (240+((60*(red-green))/delta)) :
(300+((60*(blue-green))/delta)))))));

//assign Hue = isRedMax ? HRed[8:0] : 
//(isBlueMax ? HBlue[8:0] : HGreen[8:0]); //(0-360) 9 bits
assign Saturation = (maxVal == 0) ? 8'd0 : ((delta << 8)/maxVal); //(0-255) //8Bits, max 16 bits
assign Value = maxVal; //(0-255)
//Convert back to RGB - might not be needed
// assign outputHue = (Hue % 360);
// assign outputSat = Saturation[7:0];
// assign outputVal = Value;
// assign mHSV = (outputVal - ((outputSat*outputVal)>>8)); //8bits
// assign zPartial = (((outputHue << 7)/60) % 256); //Ranges from 0 to 255
// assign zPartial2 = (zPartial > 127) ? (zPartial-128) : (127-zPartial); //Must be positive : ranges from 0 to 127
// assign zPartial3 = ((outputSat*zPartial2[7:0]) >> 7);
// assign zmSum = (outputSat > zPartial3) ? ((outputSat-zPartial3)+mHSV) : (mHSV-(zPartial3-outputSat));
// //
// assign newRed = (outputHue < 60) ? outputVal : 
// ((outputHue < 120) ? zmSum[7:0] :  
// ((outputHue < 240) ? mHSV[7:0] :
// ((outputHue < 300) ? zmSum[7:0] : outputVal )));

// assign newGreen = (outputHue < 60) ? zmSum[7:0]: 
// ((outputHue < 180) ? outputVal :
// ((outputHue < 240) ? zmSum[7:0] : mHSV[7:0]));

// assign newBlue = (outputHue < 120) ? mHSV[7:0] : 
// ((outputHue < 180) ?  zmSum[7:0] : 
// ((outputHue < 300) ?  outputVal: zmSum[7:0]));

//////////////////// Threshold sections
wire red_detect, blue_detect, green_detect, orange_detect, pink_detect, gray_detect, blueOrGreen;
////////////////////
//assign red_detect = ((compHue > 330) || (compHue < 35)) ? ((compSat > 150) ? ((compVal > 60) ? 1 : 0) : 0) : 0;
// assign red_detect = ((Hue > 330) || (Hue < 25)) ? ((Saturation > 155) ? ((Value > 80) ? 1 : 0) : 0) : 0;X
// assign blue_detect = ((Hue > 110) && (Hue < 185)) ? ((Saturation < 128) ? ((Value > 25) ? 1 : 0) : 0) : 0;
// assign green_detect = ((Hue > 110) && (Hue < 185)) ? ((Saturation > 115 && Saturation < 204) ? ((Value > 25) ? 1 : 0) : 0) : 0;
// assign pink_detect = ((Hue > 330) || (Hue < 35)) ? ((Saturation > 135 && Saturation < 195) ? ((Value > 100) ? 1 : 0) : 0) : 0;
// assign gray_detect = 0;
//assign red_detect =  (Hue < 40) ? ((Saturation > 185) ? ((Value > 105) ? 1 : 0) : 0) : 0;
assign red_detect =  ((Hue < 14) || (Hue > 350)) ? ((Saturation > 140) ? ((Value > 40) ? 1 : 0) : 0) : 0;
assign green_detect =  (Hue > 45 && Hue < 95) ? ((Saturation > 70) ? ((Value > 35) ? 1 : 0) : 0) : 0;
//assign green_detect =  (Hue > 45 && Hue < 130) ? ((Saturation > 35 && Saturation < 200) ? ((Value > 25) ? 1 : 0) : 0) : 0;
assign blue_detect =  (Hue > 40 && Hue < 100) ? ((Saturation < 155) ? ((Value > 50) ? 1 : 0) : 0) : 0;
//
//assign blue_detect = 0;
//assign green_detect = 0;
assign orange_detect = 0;
assign pink_detect = 0;
assign gray_detect = 0;
assign blueOrGreen = green_detect && blue_detect;
////////////////////
// assign newRed = (red_detect || pink_detect || gray_detect) ? 8'd255 : gray;
// assign newGreen = (green_detect || gray_detect) ? 8'd255 : gray;
// assign newBlue = (blue_detect || pink_detect) ? 8'd255 : gray;
//Red = 0, Green = 1, Blue = 2, 3 = Orange, 4 = Pink, 5 = Gray
localparam pixelRange = 31;
wire detectionArray [5:0];
//assign detectionArray = {red_detect, green_detect, blue_detect, orange_detect, pink_detect, gray_detect};
assign detectionArray[0] = red_detect;
assign detectionArray[1] = green_detect;
assign detectionArray[2] = blue_detect;
assign detectionArray[3] = orange_detect;
assign detectionArray[4] = pink_detect;
assign detectionArray[5] = gray_detect;
reg [pixelRange-1:0] pixelBuffer [5:0]; //Shift reg 
reg [9:0] xMin [5:0]; //640
reg [9:0] xMax [5:0]; //640
reg [8:0] yMin [5:0]; //480 may not be required
reg [8:0] yMax [5:0]; //480 may not be required
//Bounding boxes for next frame
reg [9:0] left [5:0]; //640
reg [9:0] right [5:0]; //640
reg [8:0] top [5:0]; //480 may not be required
reg [8:0] bottom [5:0]; //480 may not be required
wire [9:0] xDistanceVector [5:0]; //Distance between xMin and xMax
wire [8:0] yDistanceVector [5:0]; //Distance between yMin and yMax may not be required
//assign xDistanceVector = {((xMin[0] < xMax[0]) ? xMax[0]-xMin[0] : 0), ((xMin[1] < xMax[1]) ? xMax[1]-xMin[1] : 0), ((xMin[2] < xMax[2]) ? xMax[2]-xMin[2] : 0), ((xMin[3] < xMax[3]) ? xMax[3]-xMin[3] : 0), ((xMin[4] < xMax[4]) ? xMax[4]-xMin[4] : 0), ((xMin[5] < xMax[5]) ? xMax[5]-xMin[5] : 0)};
assign xDistanceVector[0] = (xMin[0] < xMax[0]) ? xMax[0]-xMin[0] : 0;
assign xDistanceVector[1] = (xMin[1] < xMax[1]) ? xMax[1]-xMin[1] : 0;
assign xDistanceVector[2] = (xMin[2] < xMax[2]) ? xMax[2]-xMin[2] : 0;
assign xDistanceVector[3] = (xMin[3] < xMax[3]) ? xMax[3]-xMin[3] : 0;
assign xDistanceVector[4] = (xMin[4] < xMax[4]) ? xMax[4]-xMin[4] : 0;
assign xDistanceVector[5] = (xMin[5] < xMax[5]) ? xMax[5]-xMin[5] : 0;
//
assign yDistanceVector[0] = (yMin[0] < yMax[0]) ? yMax[0]-yMin[0] : 0;
assign yDistanceVector[1] = (yMin[1] < yMax[1]) ? yMax[1]-yMin[1] : 0;
assign yDistanceVector[2] = (yMin[2] < yMax[2]) ? yMax[2]-yMin[2] : 0;
assign yDistanceVector[3] = (yMin[3] < yMax[3]) ? yMax[3]-yMin[3] : 0;
assign yDistanceVector[4] = (yMin[4] < yMax[4]) ? yMax[4]-yMin[4] : 0;
assign yDistanceVector[5] = (yMin[5] < yMax[5]) ? yMax[5]-yMin[5] : 0;
//assign yDistanceVector = {((yMin[0] < yMax[0]) ? yMax[0]-yMin[0] : 0), ((yMin[1] < yMax[1]) ? yMax[1]-yMin[1] : 0), ((yMin[2] < yMax[2]) ? yMax[2]-yMin[2] : 0), ((yMin[3] < yMax[3]) ? yMax[3]-yMin[3] : 0), ((yMin[4] < yMax[4]) ? yMax[4]-yMin[4] : 0), ((yMin[5] < yMax[5]) ? yMax[5]-yMin[5] : 0)};
wire [23:0] colourCodes [5:0]; //Holds output colour codes for all balls
assign colourCodes[0] = 24'hff0000; //Red
assign colourCodes[1] = 24'h00ff00; //Green
assign colourCodes[2] = 24'h0000ff; //Bluie
assign colourCodes[3] = 24'hff8000; //Orange
assign colourCodes[4] = 24'hff00ff; //Pink
assign colourCodes[5] = 24'hffffff; //Gray (white)
reg [6:0] tempCount; //Allow up to 128 detected pixels
//New implementation using detection as mode filter
//This implementation allows looser requirements on the HSV thresholds
always @(posedge clk) begin
	integer i;
	integer j;
	colourOutput = {gray, gray, gray};
	//Reset all at start of frame
	if (sop) begin
		for(i = 0; i < 6; i = i + 1) begin
			xMin[i] = 640;
			yMin[i] = 480;
			xMax[i] = 0;
			yMax[i] = 0;
		end
	end
	//Reset buffer at start of line
	if (x == 0) begin
		for(i = 0; i < 6; i = i + 1) begin
			pixelBuffer[i] = 0;
		end
	end
	//For each colour
	for(i = 0; i < 6; i = i + 1) begin
		//If a colour pixel was detected, add to buffers for that colour
		tempCount = 0;
		if(detectionArray[i] == 1) begin
			pixelBuffer[i][0] = 1;
		end
		//Count how many detected pixels 1s in buffer, if at least half the pixelrange is detected consider the pixel detected (mode filtering)
		tempCount = 0;
		for(j = 0; j < pixelRange; j = j + 1) begin
			if(pixelBuffer[i][j] == 1) begin
				tempCount = tempCount + 1;
			end
		end
		//Shift all buffers by 1 (shift register)
		pixelBuffer[i] = pixelBuffer[i]*2;
		//Mode filtering
		if (tempCount > (pixelRange/2)) begin
			xMin[i] = (xMin[i] > x) ? x : xMin[i];
			xMax[i] = (xMax[i] < x) ? x : xMax[i];
			yMin[i] = (yMin[i] > y) ? y : yMin[i];
			yMax[i] = (yMax[i] < y) ? y : yMax[i];
			//Colour output depending on the mode filtering
			colourOutput = colourCodes[i];
		end 
	end
	//Should only draw at end of frame as y keeps changing
	//If the current coordinate is an xMin, xMax, yMin or yMax of another ball, colour accordingly
	for(i = 0; i < 6; i = i + 1) begin
		if (((left[i] == x) || (right[i] == x)) || ((top[i] == y) || (bottom[i] == y))) begin
			//The difference between the two coordinates must be at least 40 to be considered
			colourOutput = ((xDistanceVector[i] > 40) && (yDistanceVector[i] > 40)) ? colourCodes[i] : gray;  
		end
	end
end

//SPI communication, constantly need to read status register to know if ready to transmit
always @(posedge clk) begin
	//Read from status register
	avalon_spi_addr <= 2;
	avalon_master_read <= 1;
	avalon_master_write <= 0;
	if (avalon_from_SPI[6] == 1) begin //If TRDY is set to 1, can transmit data
		avalon_master_read <= 0;
		avalon_spi_addr <= 1; //txdata address
		avalon_master_write <= 1;
		if ((x % 2) == 0) begin
			avalon_to_SPI <= 16'b0011100110010001; //test data
		end else begin
			avalon_to_SPI <= 16'b0111100110011001;
		end
	end

end 


// reg [8:0] hueDataBuffer [4:0]; //Store the last 5 pixel Hues
// reg [8:0] hueStack [4:0];
// reg [7:0] saturationDataBuffer [4:0]; 
// reg [7:0] saturationStack [4:0];
// reg [7:0] valueDataBuffer [4:0]; 
// reg [7:0] valueStack [4:0];
// reg [8:0] tempRegHue, compHue;
// reg [7:0] tempRegSat, tempRegVal, compSat, compVal;
// reg hueReplaced, satReplaced, valReplaced;
// localparam HueSteps = 16;
// localparam SatSteps = 4;
// localparam ValSteps = 2; 
// localparam HueIncr = 22;//360/HueSteps;
// localparam SatIncr = 63; //255/SatSteps;
// localparam ValIncr = 127; //255/ValSteps;


//Saving to data buffer
// always @(*) begin
// 	integer i;
// 	//Reset buffers at start of frame
// 	// if (sop) begin
// 	// 	for(i = 0; i < 5; i = i + 1) begin
// 	// 		hueDataBuffer[i] = 9'd0;
// 	// 		saturationDataBuffer[i] = 8'd0;
// 	// 		valueDataBuffer[i] = 8'd0;
// 	// 		hueStack[i] = 9'd0;
// 	// 		saturationStack[i] = 8'd0;
// 	// 		valueStack[i] = 8'd0;
// 	// 	end
// 	// end
// 	//Posterize/quantise values
// 	//If inbetween these two bounds, set it to whichever it is closer to
// 	// for(i = 0; i < HueSteps; i = i + 1) begin
// 	// 	//Hue
// 	// 	if ((Hue > i*HueIncr) && (Hue < (i+1)*HueIncr)) begin
// 	// 		if (Hue > (i*HueIncr)+HueIncr/2) begin
// 	// 			finalHue = (i+1)*HueIncr;
// 	// 		end else begin
// 	// 			finalHue = i*HueIncr;
// 	// 		end
// 	// 	end
// 	// 	//Sat
// 	// 	if(i < SatSteps) begin
// 	// 		if ((Saturation > i*SatIncr) && (Saturation < (i+1)*SatIncr)) begin
// 	// 			if (Saturation > (i*SatIncr)+SatIncr/2) begin
// 	// 				finalSat = (i+1)*SatIncr;
// 	// 			end else begin
// 	// 				finalSat = i*SatIncr;
// 	// 			end
// 	// 		end
// 	// 	end
// 	// 	//Val
// 	// 	if (i < ValSteps) begin
// 	// 		if ((Value > i*ValIncr) && (Value < (i+1)*ValIncr)) begin
// 	// 			if (Value > (i*ValIncr)+ValIncr/2) begin
// 	// 				finalVal = (i+1)*ValIncr;
// 	// 			end else begin
// 	// 				finalVal = i*ValIncr;
// 	// 			end
// 	// 		end
// 	// 	end
// 	// end
// 	//Save data to stacks and buffers
// 	hueReplaced = 0;
// 	satReplaced = 0;
// 	valReplaced = 0;
// 	finalHue = Hue;
// 	finalSat = Saturation[7:0];
// 	finalVal = Value;
// 	for(i = 0; i < 5; i = i + 1) begin
// 		if ((!hueReplaced) && (hueDataBuffer[i] == hueStack[x % 5])) begin
// 			hueDataBuffer[i] = finalHue;
// 			hueReplaced = 1;
// 		end
// 		if ((!satReplaced) && (saturationDataBuffer[i] == saturationStack[x % 5])) begin
// 			saturationDataBuffer[i] = finalSat;
// 			satReplaced = 1;
// 		end
// 		if ((!valReplaced) && (valueDataBuffer[i] == valueStack[x % 5])) begin
// 			valueDataBuffer[i] = finalVal;
// 			valReplaced = 1;
// 		end
// 	end 
// 	hueStack[x % 5] = finalHue;
// 	saturationStack[x % 5] = finalSat;
// 	valueStack[x % 5] = finalVal;
// 	for(i = 0; i < 4; i = i + 1) begin
// 		//Do one sweep of the arrays rightward and leftward to ensure they are sorted
// 		if(hueDataBuffer[i] > hueDataBuffer[i+1]) begin
// 			tempRegHue = hueDataBuffer[i];
// 			hueDataBuffer[i] = hueDataBuffer[i+1];
// 			hueDataBuffer[i+1] = tempRegHue;
// 		end
// 		if(saturationDataBuffer[i] > saturationDataBuffer[i+1]) begin
// 			tempRegSat = saturationDataBuffer[i];
// 			saturationDataBuffer[i] = saturationDataBuffer[i+1];
// 			saturationDataBuffer[i+1] = tempRegSat;
// 		end
// 		if(valueDataBuffer[i] > valueDataBuffer[i+1]) begin
// 			tempRegVal = valueDataBuffer[i];
// 			valueDataBuffer[i] = valueDataBuffer[i+1];
// 			valueDataBuffer[i+1] = tempRegVal;
// 		end
// 	end
// 	for(i = 4; i > 0; i = i - 1) begin
// 		//Do one sweep of the arrays rightward and leftward to ensure they are sorted
// 		if(hueDataBuffer[i] < hueDataBuffer[i-1]) begin
// 			tempRegHue = hueDataBuffer[i];
// 			hueDataBuffer[i] = hueDataBuffer[i-1];
// 			hueDataBuffer[i-1] = tempRegHue;
// 		end
// 		if(saturationDataBuffer[i] < saturationDataBuffer[i-1]) begin
// 			tempRegSat = saturationDataBuffer[i];
// 			saturationDataBuffer[i] = saturationDataBuffer[i-1];
// 			saturationDataBuffer[i-1] = tempRegSat;
// 		end
// 		if(valueDataBuffer[i] < valueDataBuffer[i-1]) begin
// 			tempRegVal = valueDataBuffer[i];
// 			valueDataBuffer[i] = valueDataBuffer[i-1];
// 			valueDataBuffer[i-1] = tempRegVal;
// 		end
// 	end
// 	//Data is now sorted across all HSV arrays, middle value is median, use threshold detection on that
// 	compHue = hueDataBuffer[2];
// 	compSat = saturationDataBuffer[2];
// 	compVal = valueDataBuffer[2];
// end
//Count valid pixels to tget the image coordinates. Reset and detect packet type on Start of Packet.
reg packet_video;
always@(posedge clk) begin
	if (sop) begin
		x <= 11'h0;
		y <= 11'h0;
		runningValueTotal <= 24'b0; //reset at the end of every frame
		packet_video <= (blue[3:0] == 3'h0);
	end
	else if (in_valid) begin
		if (x == IMAGE_W-1) begin
			x <= 11'h0;
			y <= y + 11'h1;
		end
		else begin
			x <= x + 11'h1;
			//Sample every 4 bits
			if((x % 4) == 0) begin 
				runningValueTotal <= runningValueTotal + Value;
			end
		end
	end
end

reg [1:0] msg_state;
reg [7:0] frame_count;
always@(posedge clk) begin
	integer i;
	if (eop & in_valid & packet_video) begin  //Ignore non-video packets
		//Start message writer FSM once every MSG_INTERVAL frames, if there is room in the FIFO
		frame_count <= frame_count - 1;
		//Calculate average value of the frame
		if (frame_count == 0 && msg_buf_size < MESSAGE_BUF_MAX - 3) begin
			msg_state <= 2'b01;
			frame_count <= MSG_INTERVAL-1;
		end

		//Save all bounding boxes to show next frame
		for(i = 0; i < 6; i = i + 1) begin
			left[i] = xMin[i];
			right[i] = xMax[i];
			top[i] = yMin[i];
			bottom[i] = yMax[i];
		end 

		//Calculate distance and angles
	end
	
	//Cycle through message writer states once started
	if (msg_state != 2'b00) msg_state <= msg_state + 2'b01;

end
	
//Generate output messages for CPU
reg [31:0] msg_buf_in; 
wire [31:0] msg_buf_out;
reg msg_buf_wr;
wire msg_buf_rd, msg_buf_flush;
wire [7:0] msg_buf_size;
wire msg_buf_empty;

`define RED_BOX_MSG_ID "RBB" //this is a macro

//Use to communicate with the NIOS processor
always@(*) begin	//Write words to FIFO as state machine advances
	case(msg_state)
		2'b00: begin
			msg_buf_in = 32'b0;
			msg_buf_wr = 1'b0;
		end
		default: begin
			//Communicate V with the average value
			msg_buf_in = {8'h56, runningValueTotal};
			msg_buf_wr = 1'b1;
		end
	endcase
end


//Output message FIFO
MSG_FIFO	MSG_FIFO_inst (
	.clock (clk),
	.data (msg_buf_in),
	.rdreq (msg_buf_rd),
	.sclr (~reset_n | msg_buf_flush),
	.wrreq (msg_buf_wr),
	.q (msg_buf_out),
	.usedw (msg_buf_size),
	.empty (msg_buf_empty)
	);


//Streaming registers to buffer video signal
STREAM_REG #(.DATA_WIDTH(26)) in_reg (
	.clk(clk),
	.rst_n(reset_n),
	.ready_out(sink_ready),
	.valid_out(in_valid),
	.data_out({red,green,blue,sop,eop}),
	.ready_in(out_ready),
	.valid_in(sink_valid),
	.data_in({sink_data,sink_sop,sink_eop})
);

STREAM_REG #(.DATA_WIDTH(26)) out_reg (
	.clk(clk),
	.rst_n(reset_n),
	.ready_out(out_ready),
	.valid_out(source_valid),
	.data_out({source_data,source_sop,source_eop}),
	.ready_in(source_ready),
	.valid_in(in_valid),
	.data_in({red_out, green_out, blue_out, sop, eop})
);


/////////////////////////////////
/// Memory-mapped port		 /////
/////////////////////////////////

// Addresses
`define REG_STATUS    			0
`define READ_MSG    			1
`define READ_ID    				2
`define REG_BBCOL				3

//Status register bits
// 31:16 - unimplemented
// 15:8 - number of words in message buffer (read only)
// 7:5 - unused
// 4 - flush message buffer (write only - read as 0)
// 3:0 - unused


// Process write

reg  [7:0]   reg_status;
reg	[23:0]	bb_col;

always @ (posedge clk)
begin
	if (~reset_n)
	begin
		reg_status <= 8'b0;
		bb_col <= BB_COL_DEFAULT;
	end
	else begin
		if(s_chipselect & s_write) begin
		   if      (s_address == `REG_STATUS)	reg_status <= s_writedata[7:0];
		   if      (s_address == `REG_BBCOL)	bb_col <= s_writedata[23:0];
		end
	end
end


//Flush the message buffer if 1 is written to status register bit 4
assign msg_buf_flush = (s_chipselect & s_write & (s_address == `REG_STATUS) & s_writedata[4]);


// Process reads
reg read_d; //Store the read signal for correct updating of the message buffer

// Copy the requested word to the output port when there is a read.
always @ (posedge clk)
begin
   if (~reset_n) begin
	   s_readdata <= {32'b0};
		read_d <= 1'b0;
	end
	
	else if (s_chipselect & s_read) begin
		if   (s_address == `REG_STATUS) s_readdata <= {16'b0,msg_buf_size,reg_status};
		if   (s_address == `READ_MSG) s_readdata <= {msg_buf_out};
		if   (s_address == `READ_ID) s_readdata <= 32'h1234EEE2;
		if   (s_address == `REG_BBCOL) s_readdata <= {8'h0, bb_col};
	end
	
	read_d <= s_read;
end

//Fetch next word from message buffer after read from READ_MSG
assign msg_buf_rd = s_chipselect & s_read & ~read_d & ~msg_buf_empty & (s_address == `READ_MSG);
						


endmodule

