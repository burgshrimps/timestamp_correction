# Video Timestamp Correction

## Motivation
To compare specific rodent behavior with their neuronal activity, their behavior (camera) and their neuronal activity (EEG) was recorded simultanously during an experiment. 
In order to begin further analysis one must make sure the two different signals are in sync. Due to the length of each recording (40-50 min) and a framerate of 100 FPS it is likely that the video recording is not 100% regarding the timestamp of each frame and the total number of recorded frames.

## Hard- and Software
- Highspeed camera: Genie Nano M1280 NIR
- Video Recording software: CVB Software Suite
- EEG system: Axona System

## Idea 
For the timestamp correction the following setup was used:

- CVB recorded the video signal from the camera and encoded the timestamp of each frame in an AVI container. 
- The highspeed camera sends a TTL pulse to the EEG system every time it acquired a new frame.
- A "button box" was used to transmit a TTL pulse to the EEG system every time the button was pressed. At the same time a LED lit up, clearly visible in the video recording.
- In a different script the LED timestamps are being detected in the video.
- Use the button and LED timestamps as anchor points in which we know which timestamp recorded by CVB corresponds to which (real) timestamp of when the frame got actually acquired by the camera and sent to the EEG system.

## Methods

### Axona file input
- Read in the "digitalIO" textfile from the EEG systen which contains 3 columns.
  1. time: time in seconds of corresponding event after device start.
  2. type: usually every event is type "INPUT" except for one event in the beginning of type "KEY". This column is not of particular interest for the given problem.
  3. value: encodes what kind of event was happening.
    - 4 -> camera captured frame
    - 2 -> button was pressed
    - 6 -> button was pressed while frame was captured
    - 0 -> event stopped (e.g. frame done being captured)
- Extract timestamps of when the camera acquired each frame by getting time of all events with value >= 4
- Subtract the first timestamp from every timestamp to make sure they start at 0.
- Extract the button timestamps by getting the time of all events with value == 6. Because of the high framerate of 100 FPS it is sufficient to only look for button presses among the frames.
- Filter the button timestamps because the digitalIO file contains the time for each button press as long as the button remained pressed. For the timestamp correction only the first timestamp of each button press is relevant, though.
- With the help of the button timestamps get the frame index in which the button press occured.

### CVB file input
- Read in CVB and LED timestamp textfiles
- For some unknown reason the CVB timestamps are missing a "0" at certain times (e.g. 2018/09/04 15:44:018 is written as 2018/09/04 15:44:18). This is being corrected by the function "insert_zeros()".
- Convert these timestamp strings to the same format in which the Axona timestamps are written. 
- Read in LED timestamps and frame index.

### Alignment 
- Each CVB timestamp is being aligned to a corresponding Axona timestamp which is regarded as the ground truth. 
- First assign the frames in which the LED lit up to the frames in which the button was pressed. 
- For the Axona and the CVB anchor points compare how many frames are between two successive anchor points (e.g. how many frames are between and first and the second Axona (button) anchor point compared to how many frames are between the first and the second CVB (LED) anchor point).
- Subtract the CVB anchor differences from the Axona anchor differences (-> inter_anchor_diff)
- Look at each inter_anchor_diff:

#### Case I: inter_anchor_diff == 0
Best case scenario, between these two anchor points CVB recorded as many frames as the camera acquired. Assign each CVB frame linearly to its corresponding Axona frame.

#### Case II: inter_anchor_diff > 0
There are more frames between the two button anchor points than between the two LED anchor points, meaning CVB must have skipped frame(s). It is hard to determine which exact frame was skipped due to the unreliable way in which CVB assigns timestamps to frames during recording. That's why for now the way to determine which frames are being skipped is to evenly distribute them over the interval (e.g. if two frames are being skipped skip the first after 1/3 of the interval and the second after 2/3). Not the best way, but the safest for now.

#### Case III: inter_anchor_diff < 0
There are more frames between the two LED anchor points than between the two button anchor points. Could be a result of a delay in LED detection or some problems regarding transmitting the signal inside the button box. Method is the same as in case II.

## Further observations
