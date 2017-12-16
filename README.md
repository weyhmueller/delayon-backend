# Customer Request Backend for Delay API

## Base URL

http://delayon.nodoma.in:8000/

## Routes

### get /db/:year/:month/:day/:type/:train/:station/:delay
#### What does it do
Create a Delay confirmation Dataset in the Backend from input (just for debugging and speed)

#### Parameters

| Field   | Value            | Example |
|:--------|:-----------------|:--------|
| year    | Year of travel   | 2017    |
| month   | Month of travel  | 12      |
| day     | Day of travel    | 16      |
| type    | Type of train    | ICE     |
| train   | Train number     | 703     |
| station | Station ID       | 8098160 |
| delay   | Delay in minutes | 38      |

#### Result

```
{"delayid":"CB620C"}
```


### get /delay/:year/:month/:day/:trainno/:station
#### What does it do
Create a Delay confirmation Dataset in the Backend from the Delays API

#### Parameters

| Field   | Value            | Example |
|:--------|:-----------------|:--------|
| year    | Year of travel   | 2017    |
| month   | Month of travel  | 12      |
| day     | Day of travel    | 16      |
| trainno | Train number     | 703     |
| station | Station ID       | 8098160 |

#### Result

```
{"delayid":"CB620C"}
```

### get /delay/:trainno/:station'
#### What does it do
Create a Delay confirmation Dataset in the Backend from the Delays API

#### Parameters

| Field   | Value            | Example |
|:--------|:-----------------|:--------|
| year    | Year of travel   | 2017    |
| month   | Month of travel  | 12      |
| day     | Day of travel    | 16      |
| trainno | Train number     | 703     |
| station | Station ID       | 8098160 |

#### Result

### get /pdf/:delayid
#### What does it do
Make a PDF-File for the given Delay Entry in the DB

#### Parameters

| Field   | Value                       | Example  |
|:--------|:----------------------------|:---------|
| delayid | Random ID for delay dataset | CB620C   |

#### Result

<a href="http://delayon.nodoma.in:8000/pdf/CB620C">PDF file</a>
