from setuptools import setup

# We expose the package as ComfyUI_ProxyFix while the source directory is named "ComfyUI-ProxyFix".
# This avoids a hyphen in the import name and allows: import ComfyUI_ProxyFix
setup(
    name="ComfyUI-ProxyFix",
    version="1.0.0",
    description="Fixes URL encoding issues when ComfyUI is accessed through reverse proxies",
    author="paperspace-stable-diffusion-suite",
    packages=["ComfyUI_ProxyFix"],
    package_dir={"ComfyUI_ProxyFix": "."},
    package_data={"ComfyUI_ProxyFix": ["web/__init__.py", "*.py"]},
    include_package_data=True,
    install_requires=[],
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
