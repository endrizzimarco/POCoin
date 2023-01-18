<template lang="pug">
.flex.w-full
  .flex.cursor-pointer
    img.ml-2(alt='logo', src='@/assets/logo.svg', width='35', height='35')
    p.ml-3.mt-2.text-2xl.text-white POCoin
  p.header-subtitle(style='margin-top: 0.6rem') |
  p.header-subtitle(style='margin-top: 0.7rem') A cryptocurrency visualization
  a-button.ml-auto.mr-2.text-white.top-2.bg-transparent(
    type='primary',
    href='https://github.com/endrizzimarco/POCoin/blob/master/README.md',
    target='_blank'
  ) About
</template>

<style scoped>
.header-subtitle {
  @apply font-thin text-xl text-white ml-3;
}
</style>
