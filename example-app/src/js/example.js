import { CapacitorAlarm } from 'alarm';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    CapacitorAlarm.echo({ value: inputValue })
}
