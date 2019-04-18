#!/usr/bin/env python
import unittest
from selenium import webdriver
 
 
class ExampleTest(unittest.TestCase):
 
    def setUp(self):
        """Start web driver"""
        options = webdriver.ChromeOptions()
        options.add_argument('--no-sandbox')
        options.add_argument('--headless')
        options.add_argument('--disable-gpu')
 
        self.driver = webdriver.Remote('http://0.0.0.0:4444/wd/hub', options.to_capabilities())
        self.driver.get("APPLICATION_URL")
 
    def test_search_headline(self):
        """TestCase 1"""
        title = 'DemoPipeline'
        assert title in self.driver.title
 
    def test_search_text(self):
        """TestCase 2"""
        element = self.driver.find_element_by_tag_name('body')
        assert element.text == 'Hello world...'
 
    def tearDown(self):
        """Stop web driver"""
        self.driver.quit()
 
if __name__ == "__main__":
    unittest.main(verbosity=2)
