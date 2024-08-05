export function getTempColor(t) {
	if (t >= 35) {
		return '#ff5722';
	} else if (t >= 30) {
		return '#ff9800';
	} else if (t >= 25) {
		return '#ffc107';
	} else if (t >= 18) {
		return '#4caf50';
	} else if (t > 10) {
		return '#8bc34a';
	} else if (t >= 5) {
		return '#00bcd4';
	} else if (t >= -5) {
		return '#03a9f4';
	} else {
		return '#2196f3';
	}
}

export function getHumColor(x) {
	var colors = ['#E3F2FD','#BBDEFB','#90CAF9','#64B5F6','#42A5F5','#2196F3','#1E88E5','#1976D2','#1565C0','#0D47A1','#0D47A1'];
	return colors[Math.round(x/10)];
}

function refresh() {
	var xmlHttp = new XMLHttpRequest();

	xmlHttp.onreadystatechange = function()
	{
		if (xmlHttp.readyState == XMLHttpRequest.DONE) {
		  	if (xmlHttp.status == 200)
		    {
		    	var data = JSON.parse(xmlHttp.responseText);

		    	tempGauge.setVal(data.temp).setColor(getTempColor(data.temp));
		    	humGauge.setVal(0.5).setColor(getHumColor(data.hum));
		    } else {
		    	console.log('Refresh failed: ' + xmlHttp.status);
		    }
		}
	}

	xmlHttp.open("GET", "data", true);
	xmlHttp.send();
}

// export default createVerGauge('temp', -20, 60, ' °C').setVal(0).setColor(getTempColor(0));
// export default createRadGauge('hum', 0, 100, '%').setVal(80).setColor(getHumColor(80));


// export var tempGauge = createVerGauge('temp', -20, 60, ' °C').setVal(0).setColor(getTempColor(0));
// export var humGauge = createRadGauge('hum', 0, 100, '%').setVal(80).setColor(getHumColor(80));

// document.getElementById('refresh').addEventListener('click', refresh);
// setTimeout(refresh, 100);

// var websocket = new WebSocket('ws://' + window.location.hostname + ':81');
// websocket.onmessage = function (evt) {
//  var obj = JSON.parse(evt.data);
// document.getElementById("temperature").innerHTML = obj.temperature + '&#8451';
// document.getElementById("humidity").innerHTML = obj.humidity + '%';
//  tempGauge.setVal(obj.temperature).setColor(getTempColor(obj.temperature));
//  humGauge.setVal(obj.humidity).setColor(getHumColor(obj.humidity));
// };



/////////////////////////////////////////


export function createRadGauge(id, minVal, maxVal, unit) {
    function polarToCartesian(centerX, centerY, radius, rad) {
      return {
        x: centerX + (radius * Math.cos(rad)),
        y: centerY + (radius * Math.sin(rad))
      };
    }
    
    function arc(x, y, radius, val, minVal, maxVal){
        var start = polarToCartesian(x, y, radius, -Math.PI);
        var end = polarToCartesian(x, y, radius, -Math.PI*(1 - 1/(maxVal-minVal) * (val-minVal)));
    
        var d = [
            "M", start.x, start.y, 
            "A", radius, radius, 0, 0, 1, end.x, end.y
        ].join(" ");
    
        return d;       
    }
  
    var tmpl = 
    '<svg class="rGauge" viewBox="0 0 200 145">'+ 
      '<path class="rGauge-base" id="'+id+'_base" stroke-width="30" />'+ 
      '<path class="rGauge-progress" id="'+id+'_progress" stroke-width="30" stroke="#1565c0" />'+ 
      '<text class="rGauge-val" id="'+id+'_val" x="100" y="105" text-anchor="middle"></text>'+  
      '<text class="rGauge-min-val" id="'+id+'_minVal" x="40" y="125" text-anchor="middle"></text>'+  
      '<text class="rGauge-max-val" id="'+id+'_maxVal" x="160" y="125" text-anchor="middle"></text>'+  
    '</svg>';
  
    document.getElementById(id).innerHTML = tmpl;
    document.getElementById(id+'_base').setAttribute("d", arc(100, 100, 60, 1, 0, 1));
    document.getElementById(id+'_progress').setAttribute("d", arc(100, 100, 60, minVal, minVal, maxVal));
    document.getElementById(id+'_minVal').textContent = minVal;
    document.getElementById(id+'_maxVal').textContent = maxVal;
  
    var gauge = {
      setVal: function(val) {
        val = Math.max(minVal, Math.min(val, maxVal));
        document.getElementById(id+'_progress').setAttribute("d", arc(100, 100, 60, val, minVal, maxVal));
        document.getElementById(id+'_val').textContent = val + (unit !== undefined ? unit: '');
        return gauge;
      },
       setColor: function(color) {
         document.getElementById(id+'_progress').setAttribute("stroke", color);
         return gauge;
      }
    }
    
    return gauge;
  }
  
  export function createVerGauge(id, minVal, maxVal, unit) {
    var tmpl = 
    '<svg class="vGauge" viewBox="0 0 145 145">'+
      '<rect class="vGauge-base" id="'+id+'_base" x="30" y="25" width="30" height="100"></rect>'+
      '<rect class="vGauge-progress" id="'+id+'_progress" x="30" y="25" width="30" height="0" fill="#1565c0"></rect>'+
      '<text class="vGauge-val" id="'+id+'_val" x="70" y="80" text-anchor="start"></text>'+
      '<text class="vGauge-min-val" id="'+id+'_minVal" x="70" y="125"></text>'+
      '<text class="vGauge-max-val" id="'+id+'_maxVal" x="70" y="30" text-anchor="start"></text>'+
    '</svg>';
    
    document.getElementById(id).innerHTML = tmpl;
    document.getElementById(id+'_minVal').textContent = minVal;
    document.getElementById(id+'_maxVal').textContent = maxVal;
    
    var gauge = {
      setVal: function(val) {
        val = Math.max(minVal, Math.min(val, maxVal));
        var height = 100/(maxVal-minVal) * (val-minVal);
        
        document.getElementById(id+'_progress').setAttribute("height", height);
        document.getElementById(id+'_progress').setAttribute("y", 25+(100-height));
        document.getElementById(id+'_val').textContent = val + (unit !== undefined ? unit: '');
        return gauge;
      },
      setColor: function(color) {
         document.getElementById(id+'_progress').setAttribute("fill", color);
         return gauge;
      }
    }
    
    return gauge;
  }
  