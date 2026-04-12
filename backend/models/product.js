/**
 * Product model - shape of a recommended product
 */
class Product {
  constructor({ name, price, platform, image, purchaseLink }) {
    this.name = name;
    this.price = price;
    this.platform = platform;
    this.image = image;
    this.purchaseLink = purchaseLink;
  }
}

module.exports = Product;
