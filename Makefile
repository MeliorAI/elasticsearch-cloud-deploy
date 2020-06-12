.PHONY: readme-toc clean

clean:
	find . -name 'README.md.*' -exec rm -f  {} +

readme-toc:
	# https://github.com/ekalinin/github-markdown-toc
	gh-md-toc --insert README.md
