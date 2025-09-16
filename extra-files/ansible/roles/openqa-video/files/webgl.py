#!/usr/bin/python3

import time
import re
from selenium import webdriver
from selenium.webdriver.firefox.options import Options
from selenium.webdriver.common.by import By

def get_webgl_fps_firefox() -> float:
    driver = webdriver.Firefox()
    try:
        # default values
        width = 3840
        height = 2160
        numFish = 30000
        
        # set driver window size
        driver.set_window_size(width, height)
        
        # aquarium with a lot of fish and 4K canvas
        url = f"https://webglsamples.org/aquarium/aquarium.html?numFish={numFish}&canvasWidth={width}&canvasHeight={height}"
        driver.get(url)
        
        # give time to sync
        time.sleep(15)
        
        # locate the element displaying "fps:"
        fps_text = ""
        for _ in range(5):
            try:
                # look for any element whose visible text contains "fps:"
                fps_element = driver.find_element(By.XPATH, "//*[contains(text(),'fps:')]")
                fps_text = fps_element.text or fps_element.get_attribute("innerText")
                if "fps:" in fps_text:
                    break
            except Exception:
                time.sleep(1)

        if not fps_text:
            raise RuntimeError("Unable to locate FPS element on the page")

        # extract the numeric part using regex
        match = re.search(r"fps:\s*([\d.]+)", fps_text)
        if not match:
            raise ValueError(f"FPS value not found in text '{fps_text}'")
        return float(match.group(1))
    finally:
        driver.quit()

if __name__ == "__main__":
    fps = get_webgl_fps_firefox()
    assert isinstance(fps, float) and fps > 10.0
    print(f"fps={fps:.2f}")
