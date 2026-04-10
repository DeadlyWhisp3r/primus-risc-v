import serial, time

for port in ['/dev/ttyUSB0', '/dev/ttyUSB1']:
    print(f"\nTrying {port}...")
    try:
        p = serial.Serial(port, 115200, timeout=3)
        time.sleep(0.5)
        print("Listening for 3 seconds...")
        data = p.read(10)
        print(f"Received: {data!r}")
        p.close()
    except Exception as e:
        print(f"Error: {e}")
