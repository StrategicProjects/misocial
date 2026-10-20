# Run this script in R, from the misocialr/ folder, to build the pkgdown
# site locally:
#   install.packages("pkgdown")

pkgdown::build_site()

# The site is generated in docs/ (gitignored). Open docs/index.html to
# preview. The published site is built by .github/workflows/pkgdown.yaml on
# every push to main and served from the gh-pages branch at
# https://strategicprojects.github.io/misocial/
