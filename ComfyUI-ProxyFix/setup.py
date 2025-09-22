from setuptools import setup, find_packages

setup(
    name="ComfyUI-ProxyFix",
    version="1.0.0",
    description="Fixes URL encoding issues when ComfyUI is accessed through reverse proxies",
    author="paperspace-stable-diffusion-suite",
    packages=find_packages(),
    install_requires=[
        "comfyui-frontend-package",
    ],
    entry_points={
        "comfyui.extensions": [
            "ProxyFix = ComfyUI_ProxyFix:proxy_fix",
        ]
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.8",
        "Programming Language :: Python :: 3.9",
        "Programming Language :: Python :: 3.10",
        "Programming Language :: Python :: 3.11",
    ],
    python_requires=">=3.8",
)
